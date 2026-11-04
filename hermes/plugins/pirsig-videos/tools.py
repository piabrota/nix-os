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

from .brain import Brain, BrainError, REFRESH_SECONDS, data_dir, fail, ok, open_brain, run

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


# `h:mm:ss`, `m:ss` or `s`: the form of the `t=` ranges in the reading.
def seconds(s: str) -> int:
    total = 0
    for part in s.split(":"):
        total = total * 60 + int(part)
    return total


def clock(t: float) -> str:
    t = int(t)
    return f"{t // 3600:02d}:{t // 60 % 60:02d}:{t % 60:02d}"


def brain(ctx=None) -> Brain:
    return open_brain(PLUGIN, ctx)


# `name` comes from the model: the pattern keeps it from leaving `videos/` (no `..`, no `/`).
def work_dir(name: str) -> Path:
    if not NAME.fullmatch(name or ""):
        raise BrainError(f"not a video folder name: {name!r}")
    return data_dir(PLUGIN) / "videos" / name


def video_slug(title: str) -> str:
    # videos.mjs: lower case, NFD, runs of [^a-z0-9] to one space, the first five words.
    plain = unicodedata.normalize("NFD", title.lower())
    return "-".join(re.sub(r"[^a-z0-9]+", " ", plain).split()[:5]) or "video"


def in_language(lang: str, spoken: str) -> bool:
    """`pt-BR` and `pt-orig` are both the spoken `pt`; with no known language nothing is."""
    return bool(spoken) and lang.split("-")[0] == spoken


def first_spoken(langs: list[str], spoken: str) -> str | None:
    return next((lang for lang in langs if in_language(lang, spoken)), None)


def track_names(info: dict, key: str) -> list[str]:
    return list(info.get(key) or {})


def pick_captions(info: dict) -> tuple[str | None, bool]:
    """A person's captions in the spoken language, then any person's, then the automatic
    `-orig` track of the spoken language (videos.mjs, fetchVideo). The flag is true for a
    person's captions."""
    spoken = (info.get("language") or "").split("-")[0]
    manual = [lang for lang in track_names(info, "subtitles") if lang != "live_chat"]
    sub = first_spoken(manual, spoken) or next(iter(manual), None)
    if sub:
        return sub, True
    # Only the `-orig` track is what the speaker said; the others are machine translations.
    original = [lang for lang in track_names(info, "automatic_captions") if lang.endswith("-orig")]
    return first_spoken(original, spoken), False


def transcript(events: list) -> str:
    """The json3 events in blocks of 30 s: `[00:01:30] text...`."""
    blocks: dict[int, list[str]] = {}
    for e in events:
        text = re.sub(r"\s+", " ", "".join(s.get("utf8", "") for s in e.get("segs") or [])).strip()
        if text:
            blocks.setdefault(int(e.get("tStartMs", 0) // 30000) * 30, []).append(text)
    return "".join(f"[{clock(t)}] {' '.join(lines)}\n" for t, lines in blocks.items())


def is_youtube_url(url: str) -> bool:
    return urlparse(url).scheme == "https" and (urlparse(url).hostname or "").lower() in HOSTS


# `--skip-download`: only the info and the captions, never the video file.
def ytdlp(out: str, url: str, *extra: str) -> None:
    run(["yt-dlp", "--skip-download", "--no-playlist", "--quiet", "-o", out, *extra, url],
        timeout=YTDLP_TIMEOUT)


def download_captions(tmp: Path, url: str) -> tuple[dict, str, bool]:
    """Run yt-dlp twice: first for the info, which decides the captions, then for the captions.
    Returns the info, the caption language and whether a person wrote them."""
    out = str(tmp / "v.%(ext)s")
    ytdlp(out, url, "--write-info-json")
    info = json.loads((tmp / "v.info.json").read_text(encoding="utf-8"))
    sub, manual = pick_captions(info)
    if not sub:
        raise BrainError(f"no captions in the spoken language ({info.get('language')}): "
                         "stop and tell the owner; never transcribe from memory")
    ytdlp(out, url, "--write-subs" if manual else "--write-auto-subs", "--sub-langs", sub,
          "--sub-format", "json3")
    return info, sub, manual


def write_folder(b: Brain, tmp: Path, info: dict, sub: str, manual: bool) -> tuple[dict, Path, str]:
    """Write video.json and the transcript into the work folder. Returns the video record, the
    folder and the transcript text."""
    d = info["upload_date"]
    date = f"{d[:4]}-{d[4:6]}-{d[6:]}"
    name = f"{date}-{video_slug(info['title'])}"
    # From the merge on the notes belong to the owner; a second fetch must not overwrite them.
    if (b.path / "brain" / "Videos" / name).exists():
        raise BrainError(f"{name} is already in the brain: from then on its notes are the owner's")
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
    raw = tmp / f"v.{sub}.json3"
    text = transcript(json.loads(raw.read_text(encoding="utf-8")).get("events") or [])
    (target / "transcript.txt").write_text(text, encoding="utf-8")
    shutil.copyfile(raw, target / "transcript.json3")
    return video, target, text


def fetch(args: dict, ctx=None, **_) -> str:
    url = str(args.get("url", "")).strip()
    if not is_youtube_url(url):
        return fail("give an https YouTube URL")
    try:
        b = brain(ctx)
        b.sync(max_age=REFRESH_SECONDS)
        with tempfile.TemporaryDirectory(dir=data_dir(PLUGIN)) as tmp:
            info, sub, manual = download_captions(Path(tmp), url)
            video, target, text = write_folder(b, Path(tmp), info, sub, manual)
        return ok(
            name=target.name, path=str(target), title=video["title"], channel=video["channel"],
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


def start_part(line: str, parts: list[dict]) -> dict:
    block = {"title": line[3:], "body": [], "notes": []}
    parts.append(block)
    return block


def start_note(note: re.Match, line: str, parts: list[dict], problems: list[str]) -> dict:
    if not parts:
        problems.append(f"note before the first part: {line}")
        parts.append({"title": "", "body": [], "notes": []})
    block = {"key": note[1], "from": seconds(note[2]), "to": seconds(note[3]),
             "title": note[4], "body": [], "links": []}
    parts[-1]["notes"].append(block)
    return block


def add_link(line: str, block: dict | None, problems: list[str]) -> None:
    target, _, why = line[3:].partition(": ")
    if block is None or "links" not in block:
        problems.append(f"link outside a note: {line}")
    else:
        block["links"].append({"target": target, "why": why})


def parse(text: str) -> tuple[dict, list[str]]:
    """Parts (`## `) hold notes (`### [k=key t=a-b] Title`); `-> key: why` is a link."""
    problems: list[str] = []
    parts: list[dict] = []
    title, block = "", None
    # The first matching branch wins: `### [k= t=]` is tested before the plain `### ` error, and
    # both before body text.
    for line in text.split("\n"):
        note = NOTE.match(line)
        if line.startswith("# "):
            title = line[2:]
        elif line.startswith("## "):
            block = start_part(line, parts)
        elif note:
            block = start_note(note, line, parts, problems)
        elif line.startswith("-> "):
            add_link(line, block, problems)
        elif line.startswith("### "):
            problems.append(f"note without [k= t=]: {line}")
        elif block is not None:
            block["body"].append(line)
    join_bodies(parts)
    return {"title": title, "parts": parts}, problems


def join_bodies(parts: list[dict]) -> None:
    """Turn the body lines of each part and note into one stripped string, in place."""
    for b in [x for p in parts for x in (p, *p["notes"])]:
        b["body"] = "\n".join(b["body"]).strip()


def reading_minutes(count: int, mean: float, share: float) -> int:
    """238 words a minute, rounded up; long sentences and many long words each add 15 %."""
    minutes = count / 238
    if mean > 20:
        minutes *= 1.15
    if share > 0.25:
        minutes *= 1.15
    return int(-(-minutes // 1))


def reading_text(doc: dict) -> str:
    """What a reader reads: titles and bodies, without figures and Markdown marks."""
    chunks = []
    for p in doc["parts"]:
        chunks += [p["title"], p["body"]]
        for n in p["notes"]:
            chunks += [n["title"], n["body"]]
    return re.sub(r"[*`#]", " ", FIGURE.sub("", "\n".join(chunks)))


def reading(doc: dict) -> dict:
    """Words and the reading time, by the formula in gramatico's SKILL.md (videos.mjs)."""
    text = reading_text(doc)
    words = [w for w in text.split() if re.search(r"[^\W_]", w)]
    sentences = [s for s in re.split(r"[.!?:]\s|\n+", text) if s.strip()]
    long = sum(1 for w in words if len(re.sub(r"[\W\d_]", "", w)) >= 10)
    count = len(words) or 1
    mean = count / (len(sentences) or 1)
    share = long / count
    return {"words": len(words), "mean": round(mean, 1), "long_share": round(share, 2),
            "minutes": reading_minutes(count, mean, share)}


def missing_files(path: Path) -> list[str]:
    return [f"no {f}" for f in ("video.json", "leitura.markdown", "figuras.json")
            if not (path / f).is_file()]


def coverage_problems(notes: list[dict], duration: float) -> tuple[list[str], float]:
    """The notes must cover the video from 0 to its end with no gap. Returns the problems and
    the second where the coverage stops."""
    problems = []
    covered = 0
    for start, end, key in sorted((n["from"], n["to"], n["key"]) for n in notes):
        if start > covered:
            problems.append(f"gap {clock(covered)}-{clock(start)} before {key}")
        if end <= start:
            problems.append(f"{key}: ends before it starts")
        covered = max(covered, end)
    if covered < duration - 1:
        problems.append(f"stops at {clock(covered)} of {clock(duration)}")
    return problems, covered


def key_and_link_problems(notes: list[dict]) -> list[str]:
    keys = {n["key"] for n in notes}
    problems = ["repeated note keys"] if len(keys) != len(notes) else []
    for n in notes:
        for link in n["links"]:
            # `#10` points at a note of the brain by its zid, outside this reading.
            if link["target"] not in keys and not re.match(r"#\d", link["target"]):
                problems.append(f"{n['key']}: unknown link {link['target']}")
            if not link["why"]:
                problems.append(f"{n['key']}: link to {link['target']} has no reason")
    return problems


def load_figures(path: Path) -> tuple[dict, list[str]]:
    try:
        return json.loads((path / "figuras.json").read_text(encoding="utf-8")), []
    except ValueError as e:
        return {}, [f"figuras.json is not JSON: {e}"]


def one_figure_problems(path: Path, fid: str, entry: dict | None) -> list[str]:
    if not entry:
        return [f"figure {fid} has no entry in figuras.json"]
    problems = [f"figure {fid}: no {field}" for field in FIGURE_FIELDS if not entry.get(field)]
    # The id is a file name: only these characters keep it inside figuras/.
    if not re.fullmatch(r"[a-z0-9-]+", fid) or not (path / "figuras" / f"{fid}.json").is_file():
        problems.append(f"figure {fid}: no figuras/{fid}.json (Archify's source)")
    return problems


def figure_problems(path: Path, body: str, figures: dict) -> list[str]:
    """Every figure of the text has an entry and a source; every entry is used."""
    used = list(dict.fromkeys(FIGURE.findall(body)))
    problems = []
    for fid in used:
        problems += one_figure_problems(path, fid, figures.get(fid))
    return problems + [f"figure {fid} is not in the text" for fid in figures if fid not in used]


def banned_problems(body: str) -> list[str]:
    return [f"{why}: {m.group(0)}" for pattern, why in BANNED for m in pattern.finditer(body)]


def check_dir(path: Path) -> dict:
    problems = missing_files(path)
    if problems:
        return {"problems": problems}
    video = json.loads((path / "video.json").read_text(encoding="utf-8"))
    doc, problems = parse((path / "leitura.markdown").read_text(encoding="utf-8"))
    notes = [n for p in doc["parts"] for n in p["notes"]]
    gaps, covered = coverage_problems(notes, video["duration"])
    figures, figures_file = load_figures(path)
    body = "\n".join(x["body"] for p in doc["parts"] for x in (p, *p["notes"]))
    problems += [*gaps, *key_and_link_problems(notes), *figures_file,
                 *figure_problems(path, body, figures), *banned_problems(body)]
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
        # Only the reading and the figure sources go to git; the PR body says how to fetch the
        # transcript again.
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
