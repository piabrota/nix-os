"""Videos into the pirsig brain, as a pull request.

The method is pirsig's own: `.claude/agents/video-indexer.md` and `scripts/videos.mjs` in
piabrota/pirsig. `fetch` and `check` are ports of that script's two commands, so a folder made
here passes `just video-check` there. Two steps stay on the owner's computer, because this box
has no browser and no `psg`: `just video-figures` (Archify draws the PNGs in Chrome) and
`just video-notes` (psg files the notes). The pull request says so.
"""

from __future__ import annotations

import json
import re
import shutil
import tempfile
import unicodedata
from pathlib import Path
from urllib.parse import urlparse

from .brain import Brain, BrainError, REFRESH_SECONDS, data_dir, fail, ok, run

PLUGIN = "pirsig-videos"
HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com"}
NAME = re.compile(r"\d{4}-\d\d-\d\d-[a-z0-9-]+")
NOTE = re.compile(r"^### \[k=([a-z0-9-]+) t=([\d:]+)-([\d:]+)\] (.+)$")
FIGURE = re.compile(r"^!\[fig\]\((.*)\)$", re.M)
FIGURE_FIELDS = ("title", "alt", "takeaway", "read", "missing", "evidence")
# gramatico, the mechanical part (PTW-1, PTW-4, CIE-11), as in videos.mjs.
BANNED = [
    (re.compile(r" — "), "travessão em prosa"),
    (re.compile(r"\bvale ressaltar\b|\bcabe destacar\b|\bno âmbito de\b", re.I), "enchimento"),
    (re.compile(r"\butiliz\w+", re.I), "`usar`, não `utilizar`"),
    (re.compile(r"\b(realizar|efetuar) (a|o) \w+", re.I), "verbo pleno (PTW-4)"),
    (re.compile(r"\bo mesmo\b(?= [a-z]+ (é|foi|está))", re.I), "`o mesmo` como pronome (PTW-1)"),
]
YTDLP_TIMEOUT = 300

FETCH = {
    "name": "pirsig_video_fetch",
    "description": (
        "Fetch a YouTube video's metadata and captions (no video, no audio) into a work folder, "
        "as the first step of indexing it into the owner's pirsig brain. Use only when the owner "
        "asks to index, save or study a video in pirsig. Load the skill "
        "pirsig-videos:video-indexer first. Returns the folder's name and path, the transcript's "
        "path and the path of pirsig's video-indexer policy."
    ),
    "parameters": {
        "type": "object",
        "properties": {"url": {"type": "string", "description": "The video's YouTube URL"}},
        "required": ["url"],
    },
}

CHECK = {
    "name": "pirsig_video_check",
    "description": (
        "Check a video's work folder as pirsig's `just video-check` does: every second covered "
        "by a note, unique keys, links with reasons, figure entries, gramatico's mechanical "
        "rules, and the reading time. Run it after each change to leitura.markdown."
    ),
    "parameters": {
        "type": "object",
        "properties": {"name": {"type": "string", "description": "The folder's name, <date>-<slug>"}},
        "required": ["name"],
    },
}

SUBMIT = {
    "name": "pirsig_video_submit",
    "description": (
        "Open a pull request to the owner's pirsig brain with a video's reading: video.json, "
        "leitura.markdown, figuras.json and figuras/*.json (never the transcript). Use only "
        "when pirsig_video_check passes and the owner asked to send it. Returns the URL."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "The folder's name, <date>-<slug>"},
            "request": {"type": "string", "description": "One English sentence: what the owner asked for"},
        },
        "required": ["name", "request"],
    },
}


def seconds(s: str) -> int:
    total = 0
    for part in s.split(":"):
        total = total * 60 + int(part)
    return total


def clock(t: float) -> str:
    t = int(t)
    return f"{t // 3600:02d}:{t // 60 % 60:02d}:{t % 60:02d}"


def brain(ctx=None) -> Brain:
    get = (lambda k, d: ctx.get_config(k, default=d)) if ctx is not None else (lambda k, d: d)
    return Brain(data_dir(PLUGIN), repo=get("repo", "piabrota/pirsig"), base=get("base", "main"))


def work_dir(name: str) -> Path:
    if not NAME.fullmatch(name or ""):
        raise BrainError(f"not a video folder name: {name!r}")
    return data_dir(PLUGIN) / "videos" / name


def video_slug(title: str) -> str:
    # videos.mjs: lower case, NFD, runs of [^a-z0-9] to one space, the first five words.
    plain = unicodedata.normalize("NFD", title.lower())
    return "-".join(re.sub(r"[^a-z0-9]+", " ", plain).split()[:5]) or "video"


def pick_captions(info: dict) -> tuple[str | None, bool]:
    """A person's captions in the spoken language, then any person's, then the automatic
    `-orig` track of the spoken language (videos.mjs, fetchVideo)."""
    manual = [lang for lang in (info.get("subtitles") or {}) if lang != "live_chat"]
    spoken_lang = (info.get("language") or "").split("-")[0]

    def spoken(lang: str) -> bool:
        return bool(spoken_lang) and lang.split("-")[0] == spoken_lang

    sub = next((lang for lang in manual if spoken(lang)), None) or (manual[0] if manual else None)
    if sub:
        return sub, True
    auto = next((lang for lang in (info.get("automatic_captions") or {})
                 if lang.endswith("-orig") and spoken(lang)), None)
    return auto, False


def transcript(events: list) -> str:
    """The json3 events in blocks of 30 s: `[00:01:30] text...`."""
    blocks: dict[int, list[str]] = {}
    for e in events:
        text = re.sub(r"\s+", " ", "".join(s.get("utf8", "") for s in e.get("segs") or [])).strip()
        if text:
            blocks.setdefault(int(e.get("tStartMs", 0) // 30000) * 30, []).append(text)
    return "".join(f"[{clock(t)}] {' '.join(lines)}\n" for t, lines in blocks.items())


def fetch(args: dict, ctx=None, **_) -> str:
    url = str(args.get("url", "")).strip()
    host = (urlparse(url).hostname or "").lower()
    if urlparse(url).scheme != "https" or host not in HOSTS:
        return fail("give an https YouTube URL")
    try:
        b = brain(ctx)
        b.sync(max_age=REFRESH_SECONDS)
        with tempfile.TemporaryDirectory(dir=data_dir(PLUGIN)) as tmp:
            out = str(Path(tmp) / "v.%(ext)s")

            def ytdlp(*extra: str) -> None:
                run(["yt-dlp", "--skip-download", "--no-playlist", "--quiet", "-o", out, *extra, url],
                    timeout=YTDLP_TIMEOUT)

            ytdlp("--write-info-json")
            info = json.loads((Path(tmp) / "v.info.json").read_text(encoding="utf-8"))
            sub, manual = pick_captions(info)
            if not sub:
                return fail(f"no captions in the spoken language ({info.get('language')}): "
                            "stop and tell the owner; never transcribe from memory")
            ytdlp("--write-subs" if manual else "--write-auto-subs", "--sub-langs", sub,
                  "--sub-format", "json3")
            raw = Path(tmp) / f"v.{sub}.json3"
            d = info["upload_date"]
            date = f"{d[:4]}-{d[4:6]}-{d[6:]}"
            name = f"{date}-{video_slug(info['title'])}"
            if (b.path / "brain" / "Videos" / name).exists():
                return fail(f"{name} is already in the brain: from then on its notes are the owner's")
            target = work_dir(name)
            (target / "figuras").mkdir(parents=True, exist_ok=True)
            video = {
                "id": info["id"], "url": info["webpage_url"], "title": info["title"],
                "channel": info.get("channel"), "date": date, "duration": info["duration"],
                "language": info.get("language"), "captions": sub,
                "captions_kind": "manual" if manual else "automatic",
                "description": info.get("description"), "hub": None, "resource": None,
            }
            (target / "video.json").write_text(json.dumps(video, ensure_ascii=False, indent=2) + "\n",
                                               encoding="utf-8")
            events = json.loads(raw.read_text(encoding="utf-8")).get("events") or []
            text = transcript(events)
            (target / "transcript.txt").write_text(text, encoding="utf-8")
            shutil.copyfile(raw, target / "transcript.json3")
        return ok(
            name=name, path=str(target), title=video["title"], channel=video["channel"],
            duration=clock(video["duration"]), captions=sub, captions_kind=video["captions_kind"],
            transcript=str(target / "transcript.txt"), transcript_words=len(text.split()),
            policy=str(b.path / ".claude" / "agents" / "video-indexer.md"),
            next="Read the whole transcript, then write leitura.markdown, figuras.json and "
                 "figuras/<id>.json in this folder, and run pirsig_video_check.",
        )
    except BrainError as e:
        return fail(str(e))
    except (KeyError, ValueError) as e:
        return fail(f"yt-dlp gave an unexpected answer: {e}")


def parse(text: str) -> tuple[dict, list[str]]:
    """Parts (`## `) hold notes (`### [k=key t=a-b] Title`); `-> key: why` is a link."""
    problems: list[str] = []
    parts: list[dict] = []
    title, block = "", None
    for line in text.split("\n"):
        note = NOTE.match(line)
        if line.startswith("# "):
            title = line[2:]
        elif line.startswith("## "):
            block = {"title": line[3:], "body": [], "notes": []}
            parts.append(block)
        elif note:
            if not parts:
                problems.append(f"note before the first part: {line}")
                parts.append({"title": "", "body": [], "notes": []})
            block = {"key": note[1], "from": seconds(note[2]), "to": seconds(note[3]),
                     "title": note[4], "body": [], "links": []}
            parts[-1]["notes"].append(block)
        elif line.startswith("-> "):
            target, _, why = line[3:].partition(": ")
            if block is None or "links" not in block:
                problems.append(f"link outside a note: {line}")
            else:
                block["links"].append({"target": target, "why": why})
        elif line.startswith("### "):
            problems.append(f"note without [k= t=]: {line}")
        elif block is not None:
            block["body"].append(line)
    for b in [x for p in parts for x in (p, *p["notes"])]:
        b["body"] = "\n".join(b["body"]).strip()
    return {"title": title, "parts": parts}, problems


def reading(doc: dict) -> dict:
    """Words and the reading time, by the formula in gramatico's SKILL.md (videos.mjs)."""
    chunks = []
    for p in doc["parts"]:
        chunks += [p["title"], p["body"]]
        for n in p["notes"]:
            chunks += [n["title"], n["body"]]
    text = re.sub(r"[*`#]", " ", FIGURE.sub("", "\n".join(chunks)))
    words = [w for w in text.split() if re.search(r"[^\W_]", w)]
    sentences = [s for s in re.split(r"[.!?:]\s|\n+", text) if s.strip()]
    long = sum(1 for w in words if len(re.sub(r"[\W\d_]", "", w)) >= 10)
    count = len(words) or 1
    mean = count / (len(sentences) or 1)
    share = long / count
    minutes = count / 238
    if mean > 20:
        minutes *= 1.15
    if share > 0.25:
        minutes *= 1.15
    return {"words": len(words), "mean": round(mean, 1), "long_share": round(share, 2),
            "minutes": int(-(-minutes // 1))}


def check_dir(path: Path) -> dict:
    problems: list[str] = []
    for f in ("video.json", "leitura.markdown", "figuras.json"):
        if not (path / f).is_file():
            problems.append(f"no {f}")
    if problems:
        return {"problems": problems}
    video = json.loads((path / "video.json").read_text(encoding="utf-8"))
    doc, problems = parse((path / "leitura.markdown").read_text(encoding="utf-8"))
    notes = [n for p in doc["parts"] for n in p["notes"]]

    covered = 0
    for start, end, key in sorted((n["from"], n["to"], n["key"]) for n in notes):
        if start > covered:
            problems.append(f"gap {clock(covered)}-{clock(start)} before {key}")
        if end <= start:
            problems.append(f"{key}: ends before it starts")
        covered = max(covered, end)
    if covered < video["duration"] - 1:
        problems.append(f"stops at {clock(covered)} of {clock(video['duration'])}")

    keys = {n["key"] for n in notes}
    if len(keys) != len(notes):
        problems.append("repeated note keys")
    for n in notes:
        for link in n["links"]:
            if link["target"] not in keys and not re.match(r"#\d", link["target"]):
                problems.append(f"{n['key']}: unknown link {link['target']}")
            if not link["why"]:
                problems.append(f"{n['key']}: link to {link['target']} has no reason")

    try:
        figures = json.loads((path / "figuras.json").read_text(encoding="utf-8"))
    except ValueError as e:
        figures = {}
        problems.append(f"figuras.json is not JSON: {e}")
    body = "\n".join(x["body"] for p in doc["parts"] for x in (p, *p["notes"]))
    used = list(dict.fromkeys(FIGURE.findall(body)))
    for fid in used:
        entry = figures.get(fid)
        if not entry:
            problems.append(f"figure {fid} has no entry in figuras.json")
            continue
        for field in FIGURE_FIELDS:
            if not entry.get(field):
                problems.append(f"figure {fid}: no {field}")
        if not re.fullmatch(r"[a-z0-9-]+", fid) or not (path / "figuras" / f"{fid}.json").is_file():
            problems.append(f"figure {fid}: no figuras/{fid}.json (Archify's source)")
    for fid in figures:
        if fid not in used:
            problems.append(f"figure {fid} is not in the text")

    for pattern, why in BANNED:
        problems += [f"{why}: {m.group(0)}" for m in pattern.finditer(body)]

    r = reading(doc)
    return {
        "notes": len(notes), "figures": len(figures),
        "covers": f"{clock(covered)} of {clock(video['duration'])}",
        "reading": f"Leitura estimada: ~{r['minutes']} min ({r['words']} palavras; frase média "
                   f"{r['mean']}; {round(r['long_share'] * 100)}% palavras longas)",
        "minutes": r["minutes"], "problems": problems,
        "pending": "figuras/*.png: `just video-figures` on the owner's computer (this box has no browser)",
    }


def check(args: dict, ctx=None, **_) -> str:
    try:
        result = check_dir(work_dir(str(args.get("name", ""))))
    except BrainError as e:
        return fail(str(e))
    except (KeyError, ValueError, OSError) as e:
        return fail(f"cannot read the folder: {e}")
    return ok(passed=not result["problems"], **result)


def pr_body(request: str, name: str, video: dict, result: dict, files: list[str]) -> str:
    folder = f"brain/Videos/{name}"
    return "\n".join([
        f"**Summary**: {request.strip()} This PR adds the reading of one video to `{folder}`: "
        f"{result['notes']} literature notes and {result['figures']} figure sources.",
        "",
        "**Tested**: The pirsig-videos plugin ran the checks of `just video-check`, except the PNG "
        f"check. Coverage: {result['covers']}. Reading time: about {result['minutes']} min.",
        "",
        "**What changed**",
        *(f"- `{f}`" for f in files),
        "",
        "**Video**",
        f"- {video['url']}, {clock(video['duration'])}, {video['captions_kind']} captions "
        f"(`{video['captions']}`).",
        "",
        "**To finish this PR on your computer** (the VPS has no browser and no `psg`)",
        f"1. Check out this branch. Run `just video-fetch {video['url']}` to get the transcript again. "
        "The transcript is not in git.",
        f"2. Run `just video-figures {folder}`. Look at each PNG at 800 px wide.",
        f"3. Run `just video-check {folder}`. It must pass.",
        f"4. Run `just video-notes {folder}`. Psg files the notes and copies them into brain/.",
        "5. Commit the PNGs and the notes on this branch. Then merge.",
        "",
        "**Not checked**",
        "- The text against the transcript: a reader must do this once.",
        "- The figures as pictures: Archify did not draw them yet.",
        "",
    ])


def submit(args: dict, ctx=None, **_) -> str:
    name = str(args.get("name", ""))
    request = str(args.get("request", "")).strip()
    if not request:
        return fail("say in `request` what the owner asked for")
    try:
        path = work_dir(name)
        result = check_dir(path)
        if result["problems"]:
            return fail("pirsig_video_check does not pass; fix the folder first",
                        problems=result["problems"])
        video = json.loads((path / "video.json").read_text(encoding="utf-8"))
        sources = ["video.json", "leitura.markdown", "figuras.json",
                   *sorted(f"figuras/{p.name}" for p in (path / "figuras").glob("*.json"))]
        files = {f"brain/Videos/{name}/{rel}": (path / rel).read_text(encoding="utf-8")
                 for rel in sources}
        b = brain(ctx)
        title = "videos: add the reading of one video"
        out = b.open_pr(files, f"video-{name[11:]}"[:60].rstrip("-"), title,
                        pr_body(request, name, video, result, list(files)))
        return ok(files=list(files), **out)
    except BrainError as e:
        return fail(str(e))
    except (KeyError, ValueError, OSError) as e:
        return fail(f"cannot read the folder: {e}")
