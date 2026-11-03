"""Smart notes into the pirsig brain, as a pull request.

The rules are gramatico's smart-note level (piabrota/gramatico, SKILL.md, "Smart note"), in
pirsig's fields: a note is a file of brain/Inbox/ with no `pirsig:` key and no zid, so
`psg fork import brain` gives it a zid and files it, and `psg fork export` never rewrites it.
"""

from __future__ import annotations

import re
from datetime import datetime, timedelta, timezone

from .brain import (Brain, BrainError, REFRESH_SECONDS, data_dir, fail, ok, slugify,
                    yaml_str)

PLUGIN = "pirsig-notes"
TYPES = ("fleeting", "literature", "permanent")
# `approved` is the owner's word, never the machine's (gramatico, smart note rule 6).
STATUSES = ("unverified", "partial", "verified", "open-question")
TAG = re.compile(r"[a-z0-9][a-z0-9-]*(?:/[a-z0-9][a-z0-9-]*)*")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
MAX_NOTES = 20
MAX_WORDS = 500

SEARCH = {
    "name": "pirsig_note_search",
    "description": (
        "Search the notes of the owner's pirsig brain (piabrota/pirsig, brain/Zettelkasten and "
        "brain/Inbox) by words of a title or body. Use it before pirsig_notes_submit, to find "
        "existing notes that a new note can link to. Returns each match's stem (the link "
        "target), title, zid and kind."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "Words to look for, in any order"},
            "limit": {"type": "integer", "description": "At most this many matches (1-20, default 10)"},
        },
        "required": ["query"],
    },
}

SUBMIT = {
    "name": "pirsig_notes_submit",
    "description": (
        "Open one pull request to the owner's pirsig brain with smart notes, one idea per note, "
        "following gramatico's smart-note rules. Use only when the owner asks to save, index or "
        "send notes to pirsig. Load the skill pirsig-notes:smart-notes first. Every note needs "
        "at least one link with a reason: to another note in the same call (by its title) or "
        "to an existing note (a stem from pirsig_note_search); with no known neighbour, give "
        "proposed_link instead. Returns the pull request URL."
    ),
    "parameters": {
        "type": "object",
        "properties": {
            "request": {
                "type": "string",
                "description": "One English sentence: what the owner asked for. It opens the PR body.",
            },
            "notes": {
                "type": "array",
                "description": f"1 to {MAX_NOTES} notes",
                "items": {
                    "type": "object",
                    "properties": {
                        "title": {"type": "string", "description": "The idea as a claim, in one sentence"},
                        "type": {"type": "string", "enum": list(TYPES)},
                        "status": {"type": "string", "enum": list(STATUSES)},
                        "source": {"type": "string", "description": "URL, DOI or citekey; required for literature"},
                        "tags": {"type": "array", "items": {"type": "string"}},
                        "body": {"type": "string", "description": f"The note in the writer's own words, at most {MAX_WORDS} words"},
                        "links": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "target": {"type": "string", "description": "A title in this call, or an existing note's stem"},
                                    "why": {"type": "string", "description": "Why the two notes belong together"},
                                },
                                "required": ["target", "why"],
                            },
                        },
                        "proposed_link": {
                            "type": "string",
                            "description": "With no known neighbour: the note that should exist, and why (marked ⚠)",
                        },
                    },
                    "required": ["title", "type", "status", "body"],
                },
            },
        },
        "required": ["request", "notes"],
    },
}


def brain(ctx=None) -> Brain:
    get = (lambda k, d: ctx.get_config(k, default=d)) if ctx is not None else (lambda k, d: d)
    return Brain(data_dir(PLUGIN), repo=get("repo", "piabrota/pirsig"), base=get("base", "main"))


def search(args: dict, ctx=None, **_) -> str:
    query = str(args.get("query", "")).strip().lower()
    if not query:
        return fail("no query")
    limit = max(1, min(int(args.get("limit") or 10), 20))
    try:
        b = brain(ctx)
        b.sync(max_age=REFRESH_SECONDS)
        words = query.split()
        scored = []
        for n in b.notes():
            title, body = n["title"].lower(), n["body"].lower()
            score = sum(3 * (w in title) + (w in body) for w in words)
            if score:
                scored.append((score, n))
        scored.sort(key=lambda s: -s[0])
        hits = [{k: n[k] for k in ("stem", "title", "zid", "kind", "folder")} for _, n in scored[:limit]]
        return ok(repo=b.repo, matches=hits, count=len(scored))
    except BrainError as e:
        return fail(str(e))


def words(text: str) -> int:
    return len([w for w in text.split() if re.search(r"\w", w)])


def validate(notes: list, existing: set[str]) -> list[str]:
    problems = []
    if not isinstance(notes, list) or not 1 <= len(notes) <= MAX_NOTES:
        return [f"give 1 to {MAX_NOTES} notes"]
    titles = [str(n.get("title", "")).strip() for n in notes]
    if len(set(t.lower() for t in titles)) != len(titles):
        problems.append("two notes have the same title: one idea, one note")
    for i, n in enumerate(notes, 1):
        at = f"note {i}"
        title = titles[i - 1]
        if not title or "\n" in title or len(title) > 160:
            problems.append(f"{at}: the title is one line of at most 160 characters")
        if n.get("type") not in TYPES:
            problems.append(f"{at}: type is one of {', '.join(TYPES)}")
        if n.get("status") not in STATUSES:
            problems.append(f"{at}: status is one of {', '.join(STATUSES)} (approved is the owner's word)")
        if n.get("type") == "literature" and not str(n.get("source", "")).strip():
            problems.append(f"{at}: a literature note needs its source")
        body = str(n.get("body", "")).strip()
        if not body:
            problems.append(f"{at}: no body")
        elif words(body) > MAX_WORDS:
            problems.append(f"{at}: {words(body)} words; more than {MAX_WORDS} is more than one idea")
        for text in (title, body, str(n.get("source", ""))):
            if EMAIL.search(text):
                problems.append(f"{at}: an email address; people appear by nickname only")
        for tag in n.get("tags") or []:
            if not TAG.fullmatch(str(tag)):
                problems.append(f"{at}: tag {tag!r} is not lowercase-with-hyphens")
        links = n.get("links") or []
        for link in links:
            target, why = str(link.get("target", "")).strip(), str(link.get("why", "")).strip()
            if not why:
                problems.append(f"{at}: the link to {target!r} has no reason")
            if target.lower() == title.lower():
                problems.append(f"{at}: links to itself")
            elif target.lower() not in {t.lower() for t in titles} and target not in existing:
                problems.append(f"{at}: {target!r} is no title in this call and no note in the brain")
        if not links and not str(n.get("proposed_link", "")).strip():
            problems.append(f"{at}: no link; link a neighbour or give proposed_link")
    return problems


def render(n: dict, stem_of: dict[str, str], titles: dict[str, str], created: datetime) -> str:
    tags = list(dict.fromkeys([*(n.get("tags") or []), f"status/{n['status']}", "hermes"]))
    fm = [
        "---",
        f"id: \"{created:%Y%m%d%H%M}\"",
        f"title: {yaml_str(n['title'].strip())}",
        f"kind: {n['type']}",
    ]
    if str(n.get("source", "")).strip():
        fm.append(f"source: {yaml_str(n['source'].strip())}")
    fm += [f"tags: [{', '.join(yaml_str(t) for t in tags)}]",
           f"created: {created:%Y-%m-%dT%H:%M:00+00:00}", "---", ""]
    out = "\n".join(fm) + f"\n# {n['title'].strip()}\n\n{n['body'].strip()}\n"
    if str(n.get("proposed_link", "")).strip():
        out += f"\n⚠ {n['proposed_link'].strip()}\n"
    lines = []
    for link in n.get("links") or []:
        target = link["target"].strip()
        stem = stem_of.get(target.lower(), target)
        lines.append(f"- [[{stem}]] {titles.get(stem, target)}: {link['why'].strip()}")
    if lines:
        out += "\n## Links\n\n" + "\n".join(lines) + "\n"
    return out


def build(notes: list, existing: dict[str, str], now: datetime) -> dict[str, str]:
    """The files of a submission: brain/Inbox/<id>-<slug>.md, one minute apart so each id is
    unique (gramatico's id is the UTC minute of creation)."""
    stems, titles = {}, dict(existing)
    for i, n in enumerate(notes):
        created = now + timedelta(minutes=i)
        stem = f"{created:%Y%m%d%H%M}-{slugify(n['title'])}"
        stems[n["title"].strip().lower()] = stem
        titles[stem] = n["title"].strip()
        n["_created"] = created
    files = {}
    for n in notes:
        stem = stems[n["title"].strip().lower()]
        files[f"brain/Inbox/{stem}.md"] = render(n, stems, titles, n["_created"])
    return files


def pr_body(request: str, notes: list, files: dict[str, str]) -> str:
    rows = "\n".join(f"- `{path}`: {n['type']}, {n['status']}. {n['title'].strip()}"
                     for path, n in zip(files, notes))
    flagged = [n["title"].strip() for n in notes if str(n.get("proposed_link", "")).strip()]
    return "\n".join([
        f"**Summary**: {request.strip()} This PR adds {len(notes)} smart notes to brain/Inbox/.",
        "",
        "**Tested**: The pirsig-notes plugin checked the mechanical smart-note rules. "
        "A person must read each note against its source.",
        "",
        "**What changed**",
        rows,
        "",
        "**After the merge**",
        "1. Run `psg fork import brain`. Pirsig gives each note a zid and imports its links.",
        "2. Read each note. Change `status` only when you checked the source.",
        "",
        "**Not checked**",
        "- Own words, one idea per note, and names of people: these need a reader.",
        *(f"- ⚠ No known neighbour: {t}" for t in flagged),
        "",
    ])


def submit(args: dict, ctx=None, **_) -> str:
    notes = args.get("notes")
    request = str(args.get("request", "")).strip()
    if not request:
        return fail("say in `request` what the owner asked for")
    try:
        b = brain(ctx)
        b.sync()
        existing = {n["stem"]: n["title"] for n in b.notes()}
        problems = validate(notes, set(existing))
        if problems:
            return fail("the notes break the smart-note rules; fix them and call again", problems=problems)
        now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
        files = build(notes, existing, now)
        first = notes[0]["title"].strip()
        count = len(notes)
        title = f"notes: add {count} smart note{'s' if count > 1 else ''} to the inbox"
        result = b.open_pr(files, f"notes-{slugify(first, 5)}", title, pr_body(request, notes, files))
        return ok(files=list(files), **result)
    except BrainError as e:
        return fail(str(e))
