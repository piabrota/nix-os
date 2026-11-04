#!/usr/bin/env python3
"""Build the personal feed: fetch the sources, score every item, write the outputs.

Standard library only. A no_agent cron job runs it and posts the digest of new items from stdout.
See docs/FEEDS.md.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import io
import json
import math
import os
import re
import sys
import tempfile
import threading
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterator, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from itertools import zip_longest
from pathlib import Path
from xml.etree import ElementTree as ET
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

USER_AGENT = "Mozilla/5.0 (compatible; piabrota-feed/1.0; +https://github.com/piabrota/nix-os)"
TIMEOUT = 20.0
RETRY_WAIT = 2.0
MAX_BYTES = 1_500_000
WORKERS = 4
GITHUB_HOST = "api.github.com"
GITHUB_GAP = 7.0
SUMMARY_MAX = 400
SEEN_DAYS = 60
INTEREST_CAP = 8.0
ZONE = "America/Sao_Paulo"
FEED_ID = "tag:piabrota.art,2026:feed:personal"
ITEM_ID_PREFIX = "tag:piabrota.art,2026:item:"
ATOM = "http://www.w3.org/2005/Atom"
KINDS = ("feed", "github_search", "apple_chart")
ENTRY_TAGS = frozenset({"item", "entry"})
DATE_TAGS = ("pubDate", "updated", "published", "date")
SUMMARY_TAGS = ("description", "summary", "encoded", "content")

BLOCK_RE = re.compile(r"</?(?:p|br|div|li|ul|ol|h[1-6]|tr|td|table|blockquote|pre)\b[^>]*>", re.IGNORECASE)
TAG_RE = re.compile(r"</?[A-Za-z!][^>]*>")
SPACE_RE = re.compile(r"\s+")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
MARKDOWN_RE = re.compile(r"([\\`*_{}\[\]<>()#+!|~])")
DAYS_RE = re.compile(r"\{d(\d+)\}")

Fetch = Callable[[str, dict[str, str]], bytes]


class FeedError(Exception):
    """A failure that ends the run with exit code 1."""


# ---------------------------------------------------------------- data


@dataclass(frozen=True)
class Output:
    max_items: int = 80
    max_per_group: int = 14
    max_age_days: int = 21
    min_score: float = 4.0
    digest_items: int = 18
    digest_per_group: int = 3
    digest_min_score: float = 6.0
    digest_max_chars: int = 1900
    pinned_keep: int = 3


@dataclass(frozen=True)
class Group:
    id: str
    title: str


@dataclass(frozen=True)
class Interest:
    name: str
    weight: int
    pattern: re.Pattern[str]


@dataclass(frozen=True)
class Source:
    id: str
    group: str
    kind: str
    weight: int
    max_age_days: int
    pinned_keep: int
    url: str = ""
    query: str = ""
    limit: int = 20
    pinned: bool = False
    requires_match: bool = False
    genres: tuple[str, ...] = ()
    exclude_terms: tuple[str, ...] = ()


@dataclass(frozen=True)
class Config:
    title: str
    output: Output
    negative: re.Pattern[str]
    groups: tuple[Group, ...]
    interests: tuple[Interest, ...]
    sources: tuple[Source, ...]


@dataclass(frozen=True)
class Item:
    title: str
    link: str
    summary: str
    date: datetime
    dated: bool
    source: str
    group: str
    stars: int = 0
    score: float = 0.0
    matched: tuple[str, ...] = ()
    pinned: bool = False


@dataclass(frozen=True)
class SourceResult:
    id: str
    status: str  # "ok", "error" or "skipped"
    items: tuple[Item, ...] = ()
    error: str = ""


@dataclass(frozen=True)
class Run:
    cfg: Config
    fetch: Fetch
    now: datetime
    deadline: float


@dataclass(frozen=True)
class Report:
    cfg: Config
    sources: Sequence[Source]
    results: Sequence[SourceResult]
    items: Sequence[Item]
    errors: tuple[str, ...]
    now: datetime


@dataclass(frozen=True)
class Paths:
    out: Path
    state: Path


# ---------------------------------------------------------------- config


def compile_terms(terms: Sequence[str]) -> re.Pattern[str]:
    """One case-insensitive pattern that matches any term as a whole word or phrase."""
    if not terms:
        return re.compile(r"(?!)")
    body = "|".join(re.escape(t) for t in sorted(terms, key=len, reverse=True))
    return re.compile(rf"(?<!\w)(?:{body})(?!\w)", re.IGNORECASE)


def parse_source(raw: dict, output: Output) -> Source:
    """Build a source; a missing age limit or pin count comes from [output]."""
    fields = {"max_age_days": output.max_age_days, "pinned_keep": output.pinned_keep, **raw}
    fields["genres"] = tuple(fields.get("genres", ()))
    fields["exclude_terms"] = tuple(fields.get("exclude_terms", ()))
    return Source(**fields)


def check_sources(sources: Sequence[Source], groups: Sequence[Group]) -> None:
    """Reject a duplicate id, an unknown group or an unknown kind."""
    known = {g.id for g in groups}
    seen: set[str] = set()
    for src in sources:
        if src.id in seen:
            raise FeedError(f"duplicate source id: {src.id}")
        if src.group not in known or src.kind not in KINDS:
            raise FeedError(f"source {src.id}: unknown group or kind")
        seen.add(src.id)


def parse_config(raw: dict) -> Config:
    """Turn the TOML tables into a Config."""
    output = Output(**raw.get("output", {}))
    groups = tuple(Group(g["id"], g["title"]) for g in raw.get("group", []))
    interests = tuple(
        Interest(t["name"], t["weight"], compile_terms(t["terms"])) for t in raw.get("interest", [])
    )
    sources = tuple(parse_source(s, output) for s in raw.get("source", []))
    check_sources(sources, groups)
    negative = compile_terms(raw.get("negative", {}).get("terms", []))
    return Config(raw["title"], output, negative, groups, interests, sources)


def load_config(path: Path) -> Config:
    """Read and check the configuration file."""
    with path.open("rb") as handle:
        raw = tomllib.load(handle)
    try:
        return parse_config(raw)
    except (KeyError, TypeError) as exc:
        raise FeedError(f"{path}: bad configuration: {exc!r}") from exc


def select_sources(cfg: Config, ids: Sequence[str]) -> list[Source]:
    """The sources named by --source, or all of them."""
    return [s for s in cfg.sources if not ids or s.id in ids]


# ---------------------------------------------------------------- text and dates


def clean_text(text: str) -> str:
    """Remove HTML tags, entities, control characters and extra white space."""
    unescaped = html.unescape(TAG_RE.sub("", BLOCK_RE.sub(" ", text)))
    return SPACE_RE.sub(" ", CONTROL_RE.sub("", unescaped)).strip()


def summarize(text: str) -> str:
    """Clean text, cut at SUMMARY_MAX characters."""
    return clean_text(text)[:SUMMARY_MAX].rstrip()


def to_utc(moment: datetime) -> datetime:
    """A naive time is UTC."""
    if moment.tzinfo is None:
        return moment.replace(tzinfo=timezone.utc)
    return moment.astimezone(timezone.utc)


def parse_date(text: str) -> datetime | None:
    """ISO 8601 or RFC 822 text to a UTC time; None when it is neither."""
    text = text.strip()
    for parse in (datetime.fromisoformat, parsedate_to_datetime):
        try:
            return to_utc(parse(text))
        except (TypeError, ValueError):
            continue
    return None


def iso_z(moment: datetime) -> str:
    """UTC time as 2026-11-04T10:00:00Z."""
    return to_utc(moment).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalise_link(link: str) -> str:
    """Lower-case host, no utm_* keys, no fragment, no trailing slash."""
    parts = urllib.parse.urlsplit(link.strip())
    pairs = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query = urllib.parse.urlencode([(k, v) for k, v in pairs if not k.lower().startswith("utm_")])
    path = parts.path.rstrip("/")
    return urllib.parse.urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, query, ""))


def normalise_title(title: str) -> str:
    """Lower case words only, for the second dedupe pass."""
    return re.sub(r"\W+", " ", title.lower()).strip()


def item_id(link: str) -> str:
    """The first 16 hex characters of the SHA-256 of the normalised link."""
    return hashlib.sha256(normalise_link(link).encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------- parsing


def local(tag: str) -> str:
    """The tag name without its namespace."""
    return tag.rsplit("}", 1)[-1]


def child_text(elem: ET.Element, names: Sequence[str]) -> str:
    """Text of the first child that has one of the names; earlier names win."""
    for name in names:
        for child in elem:
            text = "".join(child.itertext()).strip() if local(child.tag) == name else ""
            if text:
                return text
    return ""


def entry_link(elem: ET.Element) -> str:
    """The alternate link of an Atom entry, or the text of an RSS link."""
    fallback = ""
    for child in elem:
        if local(child.tag) != "link":
            continue
        target = child.get("href") or (child.text or "").strip()
        if target and child.get("rel") in (None, "alternate"):
            return target
        fallback = fallback or target
    return fallback


def parse_entry(elem: ET.Element, src: Source, now: datetime) -> Item | None:
    """One RSS item or Atom entry; None when it has no link."""
    link = entry_link(elem)
    if not link:
        return None
    moment = parse_date(child_text(elem, DATE_TAGS))
    return Item(
        title=clean_text(child_text(elem, ("title",))) or link,
        link=link,
        summary=summarize(child_text(elem, SUMMARY_TAGS)),
        date=moment or now,
        dated=moment is not None,
        source=src.id,
        group=src.group,
    )


def iter_entries(data: bytes) -> Iterator[ET.Element]:
    """Complete item and entry elements, in order, as the parser reaches them."""
    for _, elem in ET.iterparse(io.BytesIO(data), events=("end",)):
        if local(elem.tag) in ENTRY_TAGS:
            yield elem


def parse_feed(data: bytes, src: Source, now: datetime) -> list[Item]:
    """The first src.limit items of an RSS or Atom document. A cut document is fine."""
    items: list[Item] = []
    try:
        for elem in iter_entries(data):
            item = parse_entry(elem, src, now)
            if item:
                items.append(item)
            if len(items) >= src.limit:
                break
    except ET.ParseError:
        if not items:
            raise
    return items


def github_item(repo: dict, src: Source, now: datetime) -> Item:
    """One repository of a search result. Its date is the last push, else the creation."""
    moment = parse_date(repo.get("pushed_at") or "") or parse_date(repo.get("created_at") or "")
    return Item(
        title=repo["full_name"],
        link=repo["html_url"],
        summary=summarize(repo.get("description") or ""),
        date=moment or now,
        dated=moment is not None,
        source=src.id,
        group=src.group,
        stars=int(repo.get("stargazers_count") or 0),
    )


def parse_github(data: bytes, src: Source, now: datetime) -> list[Item]:
    """Items of a GitHub repository search."""
    repos = json.loads(data).get("items", [])
    return [github_item(repo, src, now) for repo in repos[: src.limit]]


def apple_item(entry: dict, src: Source, now: datetime) -> Item | None:
    """One podcast of the chart; None when its genres are not wanted. It has no date."""
    genres = [g.get("name", "") for g in entry.get("genres", [])]
    if src.genres and not set(genres) & set(src.genres):
        return None
    return Item(
        title=clean_text(entry["name"]),
        link=entry["url"],
        summary=summarize(f"{entry.get('artistName', '')}. {', '.join(genres)}"),
        date=now,
        dated=False,
        source=src.id,
        group=src.group,
    )


def parse_apple(data: bytes, src: Source, now: datetime) -> list[Item]:
    """Items of an Apple podcast chart."""
    results = json.loads(data)["feed"]["results"][: src.limit]
    items = (apple_item(entry, src, now) for entry in results)
    return [item for item in items if item]


# ---------------------------------------------------------------- scoring


def interest_points(interest: Interest, item: Item) -> float:
    """Title match: 3 * weight / 5 * 2. Summary match: 1 * weight / 5 * 2. Else 0."""
    if interest.pattern.search(item.title):
        return 3 * interest.weight / 5 * 2
    if interest.pattern.search(item.summary):
        return 1 * interest.weight / 5 * 2
    return 0.0


def interest_score(item: Item, interests: Sequence[Interest]) -> tuple[float, list[str]]:
    """The summed interest points, capped, and the names of the interests that matched."""
    points = [(i.name, interest_points(i, item)) for i in interests]
    hits = [(name, value) for name, value in points if value > 0]
    return min(INTEREST_CAP, sum(value for _, value in hits)), [name for name, _ in hits]


def recency_bonus(item: Item, src: Source, now: datetime) -> float:
    """+2 under 24 hours, then a straight line down to 0 at max_age_days. None without a date."""
    if not item.dated:
        return 0.0
    age_days = (now - item.date).total_seconds() / 86400
    span = src.max_age_days - 1
    if age_days <= 1:
        return 2.0
    return max(0.0, 2.0 * (1 - (age_days - 1) / span)) if span > 0 else 0.0


def stars_bonus(stars: int) -> float:
    """Up to +3 for a popular repository."""
    return min(3.0, math.log10(stars + 1) / 1.5)


def too_old(item: Item, src: Source, now: datetime) -> bool:
    """A dated item older than the source limit."""
    return item.dated and now - item.date > timedelta(days=src.max_age_days)


def is_excluded(item: Item, src: Source) -> bool:
    """The title has a term of the source exclude_terms, as a whole word or phrase."""
    return bool(compile_terms(src.exclude_terms).search(item.title))


def score_item(item: Item, src: Source, cfg: Config, now: datetime) -> Item | None:
    """The item with its score, or None when a rule drops it."""
    if cfg.negative.search(item.title) or cfg.negative.search(item.summary):
        return None
    if too_old(item, src, now) or is_excluded(item, src):
        return None
    interest, matched = interest_score(item, cfg.interests)
    if src.requires_match and not matched:
        return None
    total = src.weight + interest + recency_bonus(item, src, now) + stars_bonus(item.stars)
    return replace(item, score=round(total, 1), matched=tuple(matched))


def pinned_links(scored: Sequence[Item], src: Source) -> set[str]:
    """Links of the newest pinned_keep items of a pinned source."""
    if not src.pinned:
        return set()
    newest = sorted(scored, key=lambda i: i.date, reverse=True)[: src.pinned_keep]
    return {i.link for i in newest}


def select_items(src: Source, items: Sequence[Item], cfg: Config, now: datetime) -> list[Item]:
    """Score the items of one source and keep those above min_score, and the pinned ones."""
    scored = [s for s in (score_item(i, src, cfg, now) for i in items) if s]
    pinned = pinned_links(scored, src)
    marked = [replace(i, pinned=i.link in pinned) for i in scored]
    return [i for i in marked if i.score >= cfg.output.min_score or i.pinned]


def best_by(items: Sequence[Item], key: Callable[[Item], str]) -> list[Item]:
    """One item for each key: the highest score, then the newest. An empty key never merges."""
    best: dict[str, Item] = {}
    for position, item in enumerate(items):
        name = key(item) or f"#{position}"
        current = best.get(name)
        if current is None or (item.score, item.date) > (current.score, current.date):
            best[name] = item
    return list(best.values())


def dedupe(items: Sequence[Item]) -> list[Item]:
    """By normalised link first, then by normalised title."""
    by_link = best_by(items, lambda i: normalise_link(i.link))
    return best_by(by_link, lambda i: normalise_title(i.title))


def rank(items: Sequence[Item]) -> list[Item]:
    """Best score first, then newest."""
    return sorted(items, key=lambda i: (-i.score, -i.date.timestamp()))


def share_key(item: Item) -> tuple[bool, float, float]:
    """The order inside a group for the feed: pinned first, then score, then date."""
    return (item.pinned, item.score, item.date.timestamp())


def best_key(item: Item) -> tuple[float, float]:
    """The order inside a group for the digest: score, then date."""
    return (item.score, item.date.timestamp())


def split_shares(items: Sequence[Item], share: int, key: Callable[[Item], tuple]) -> tuple[list[Item], list[Item]]:
    """The best `share` items of each group, and all the others. Both lists keep the order of key."""
    taken: list[Item] = []
    rest: list[Item] = []
    counts: dict[str, int] = {}
    for item in sorted(items, key=key, reverse=True):
        count = counts.get(item.group, 0)
        (taken if count < share else rest).append(item)
        counts[item.group] = count + 1
    return taken, rest


def select_for_feed(items: Sequence[Item], output: Output) -> list[Item]:
    """Each group gets max_per_group places first. The room that is left goes to the best of the rest."""
    first, rest = split_shares(items, output.max_per_group, share_key)
    chosen = first + rank(rest)[: max(0, output.max_items - len(first))]
    return rank(sorted(chosen, key=share_key, reverse=True)[: output.max_items])


def select_for_digest(items: Sequence[Item], output: Output) -> list[Item]:
    """At most digest_per_group items of each group, best first, cut at digest_items."""
    taken, _ = split_shares(items, output.digest_per_group, best_key)
    return rank(taken)[: output.digest_items]


# ---------------------------------------------------------------- network


def is_timeout(exc: BaseException) -> bool:
    """A timeout, plain or wrapped by urllib."""
    if isinstance(exc, urllib.error.URLError) and not isinstance(exc, urllib.error.HTTPError):
        return isinstance(exc.reason, TimeoutError)
    return isinstance(exc, TimeoutError)


def is_retryable(exc: OSError) -> bool:
    """A timeout or an HTTP 5xx. Never a 4xx."""
    if isinstance(exc, urllib.error.HTTPError):
        return exc.code >= 500
    return is_timeout(exc)


def get_with_retry(do: Callable[[], bytes], sleep: Callable[[float], None]) -> bytes:
    """Call do. After a retryable error, wait RETRY_WAIT seconds and call it once more."""
    try:
        return do()
    except OSError as exc:
        if not is_retryable(exc):
            raise
    sleep(RETRY_WAIT)
    return do()


def host_gap(host: str) -> float:
    """Seconds between two requests to the host: GitHub's anonymous limit is 10 a minute."""
    return GITHUB_GAP if host == GITHUB_HOST else 0.0


class Fetcher:
    """HTTP client: one request per host at a time, a gap between GitHub queries, one retry."""

    def __init__(
        self,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._sleep = sleep
        self._clock = clock
        self._guard = threading.Lock()
        self._locks: dict[str, threading.Lock] = {}
        self._last: dict[str, float] = {}

    def __call__(self, url: str, headers: dict[str, str]) -> bytes:
        host = urllib.parse.urlsplit(url).hostname or ""
        with self._lock_for(host):
            self._throttle(host)
            try:
                return get_with_retry(lambda: self._open(url, headers), self._sleep)
            finally:
                self._last[host] = self._clock()

    def _lock_for(self, host: str) -> threading.Lock:
        with self._guard:
            return self._locks.setdefault(host, threading.Lock())

    def _throttle(self, host: str) -> None:
        wait = self._last.get(host, -math.inf) + host_gap(host) - self._clock()
        if wait > 0:
            self._sleep(wait)

    def _open(self, url: str, headers: dict[str, str]) -> bytes:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **headers})
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return response.read(MAX_BYTES)


def github_query(query: str, now: datetime) -> str:
    """Replace {d7}, {d14}, {d30} with the date that many days ago."""
    return DAYS_RE.sub(lambda m: (now - timedelta(days=int(m[1]))).strftime("%Y-%m-%d"), query)


def github_url(src: Source, now: datetime) -> str:
    """The repository search URL of a github_search source."""
    params = {
        "q": github_query(src.query, now),
        "sort": "stars",
        "order": "desc",
        "per_page": src.limit,
    }
    return "https://api.github.com/search/repositories?" + urllib.parse.urlencode(params)


def github_headers(environ: dict[str, str]) -> dict[str, str]:
    """The Accept header, and a token only when GITHUB_TOKEN is set."""
    headers = {"Accept": "application/vnd.github+json"}
    if environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {environ['GITHUB_TOKEN']}"
    return headers


def request_for(src: Source, now: datetime) -> tuple[str, dict[str, str]]:
    """The URL and the extra headers of a source."""
    if src.kind == "github_search":
        return github_url(src, now), github_headers(dict(os.environ))
    return src.url, {}


def host_of(src: Source) -> str:
    """The host that a source asks."""
    if src.kind == "github_search":
        return GITHUB_HOST
    return urllib.parse.urlsplit(src.url).hostname or ""


def describe_error(exc: Exception) -> str:
    """A short text for health.json."""
    if isinstance(exc, urllib.error.HTTPError):
        text = f"HTTP {exc.code}"
    elif is_timeout(exc):
        text = "timeout"
    else:
        text = f"{type(exc).__name__}: {exc}"
    return text[:200]


def load_items(src: Source, run: Run) -> list[Item]:
    """Fetch one source and parse it."""
    url, headers = request_for(src, run.now)
    data = run.fetch(url, headers)
    parsers = {"feed": parse_feed, "github_search": parse_github, "apple_chart": parse_apple}
    return parsers[src.kind](data, src, run.now)


def run_source(src: Source, run: Run) -> SourceResult:
    """Fetch and parse one source. Never raise: record the error."""
    if time.monotonic() >= run.deadline:
        return SourceResult(src.id, "skipped")
    try:
        return SourceResult(src.id, "ok", tuple(load_items(src, run)))
    except Exception as exc:  # the edge of one source: a failure must not stop the run
        return SourceResult(src.id, "error", error=describe_error(exc))


def interleave(sources: Sequence[Source]) -> list[Source]:
    """Spread the sources of one host, so the four workers do not wait on one host lock."""
    by_host: dict[str, list[Source]] = {}
    for src in sources:
        by_host.setdefault(host_of(src), []).append(src)
    return [s for tier in zip_longest(*by_host.values()) for s in tier if s]


def collect(sources: Sequence[Source], run: Run) -> list[SourceResult]:
    """Run all sources on a small thread pool. The results follow the order of sources."""
    order = interleave(sources)
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        done = dict(zip((s.id for s in order), pool.map(lambda s: run_source(s, run), order)))
    return [done[s.id] for s in sources]


# ---------------------------------------------------------------- outputs


def make_report(cfg: Config, sources: Sequence[Source], results: Sequence[SourceResult], now: datetime) -> Report:
    """Score, dedupe and rank the items of all sources that worked."""
    kept = [i for s, r in zip(sources, results) for i in select_items(s, r.items, cfg, now)]
    items = select_for_feed(dedupe(kept), cfg.output)
    errors = tuple(r.id for r in results if r.status == "error")
    return Report(cfg, sources, results, items, errors, now)


def atom_text(parent: ET.Element, name: str, text: str) -> ET.Element:
    """Add a child element that holds text. The root element sets the Atom namespace."""
    child = ET.SubElement(parent, name)
    child.text = text
    return child


def detail_line(item: Item) -> str:
    """score N.N - source id - matched names"""
    parts = [f"score {item.score:.1f}", item.source]
    if item.matched:
        parts.append(", ".join(item.matched))
    if item.stars:
        parts.append(f"{item.stars} stars")
    return " - ".join(parts)


def build_entry(item: Item) -> ET.Element:
    """One Atom entry."""
    entry = ET.Element("entry")
    atom_text(entry, "title", f"[{item.group}] {item.title}")
    ET.SubElement(entry, "link", rel="alternate", href=item.link)
    atom_text(entry, "id", ITEM_ID_PREFIX + item_id(item.link))
    atom_text(entry, "updated", iso_z(item.date))
    atom_text(entry, "summary", f"{detail_line(item)}\n{item.summary}").set("type", "text")
    for term in (item.group, *item.matched):
        ET.SubElement(entry, "category", term=term)
    return entry


def build_atom(report: Report) -> bytes:
    """The Atom 1.0 feed."""
    feed = ET.Element("feed", xmlns=ATOM)
    atom_text(feed, "id", FEED_ID)
    atom_text(feed, "title", report.cfg.title)
    atom_text(feed, "updated", iso_z(report.now))
    atom_text(ET.SubElement(feed, "author"), "name", report.cfg.title)
    feed.extend(build_entry(item) for item in report.items)
    return ET.tostring(feed, encoding="utf-8", xml_declaration=True)


def build_opml(cfg: Config, sources: Sequence[Source]) -> bytes:
    """OPML 2.0 with one outline per group and one rss outline per feed source."""
    root = ET.Element("opml", version="2.0")
    ET.SubElement(ET.SubElement(root, "head"), "title").text = cfg.title
    body = ET.SubElement(root, "body")
    for group in cfg.groups:
        feeds = [s for s in sources if s.group == group.id and s.kind == "feed"]
        outline = ET.SubElement(body, "outline", text=group.title, title=group.title) if feeds else None
        for src in feeds:
            ET.SubElement(outline, "outline", type="rss", text=src.id, title=src.id, xmlUrl=src.url)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def health_entry(result: SourceResult) -> dict:
    """Status, error, item count and newest item date of one source."""
    dated = [i.date for i in result.items if i.dated]
    return {
        "status": result.status,
        "error": result.error or None,
        "items": len(result.items),
        "newest": iso_z(max(dated)) if dated else None,
    }


def build_health(report: Report) -> bytes:
    """health.json."""
    sources = {s.id: health_entry(r) for s, r in zip(report.sources, report.results)}
    document = {"generated": iso_z(report.now), "sources": sources}
    return (json.dumps(document, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def local_date(now: datetime) -> date:
    """Today's date in Sao Paulo."""
    try:
        zone = ZoneInfo(ZONE)
    except ZoneInfoNotFoundError:
        zone = timezone(timedelta(hours=-3))  # Brazil has had no summer time since 2019
    return now.astimezone(zone).date()


def age_label(item: Item, now: datetime) -> str:
    """Age as 5h or 2d."""
    if not item.dated:
        return "n/a"
    hours = max(0, int((now - item.date).total_seconds() // 3600))
    return f"{hours}h" if hours < 24 else f"{hours // 24}d"


def item_lines(item: Item, now: datetime) -> list[str]:
    """The score line, and the link in angle brackets so Discord shows no preview."""
    title = MARKDOWN_RE.sub(r"\\\1", item.title)
    link = item.link.replace(">", "%3E").replace(" ", "%20")
    return [f"- **{item.score:.1f}** {title} - {item.source}, {age_label(item, now)}", f"  <{link}>"]


def render_digest(items: Sequence[Item], cfg: Config, now: datetime, errors: Sequence[str]) -> str:
    """Markdown: a dated heading, one section per group in config order, an error line."""
    lines = [f"# Digest {local_date(now).isoformat()}"]
    for group in cfg.groups:
        rows = [i for i in items if i.group == group.id]
        if rows:
            lines += ["", f"## {group.title}"]
            lines += [line for item in rows for line in item_lines(item, now)]
    if errors:
        lines += ["", f"Sources with errors: {', '.join(errors)}"]
    return "\n".join(lines) + "\n"


def pick_digest(items: Sequence[Item], report: Report, max_chars: int | None = None) -> list[Item]:
    """The best digest items: a share for each group, cut at digest_items. With max_chars, drop the last until the text fits."""
    chosen = select_for_digest(items, report.cfg.output)
    while max_chars and chosen:
        text = render_digest(chosen, report.cfg, report.now, report.errors)
        if len(text) <= max_chars:
            break
        chosen.pop()
    return chosen


def write_atomic(path: Path, data: bytes) -> None:
    """Write a temporary file in the same folder, then rename it over the target."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(data)
        os.replace(temp, path)
    except OSError:
        Path(temp).unlink(missing_ok=True)
        raise


def write_outputs(report: Report, out: Path) -> None:
    """feed.atom, digest.md, sources.opml and health.json."""
    chosen = pick_digest(report.items, report)
    digest = render_digest(chosen, report.cfg, report.now, report.errors)
    files = {
        "feed.atom": build_atom(report),
        "digest.md": digest.encode("utf-8"),
        "sources.opml": build_opml(report.cfg, report.sources),
        "health.json": build_health(report),
    }
    for name, data in files.items():
        write_atomic(out / name, data)


# ---------------------------------------------------------------- state


def load_state(path: Path) -> dict[str, str]:
    """The seen items: id to first-seen date. A missing or damaged file is an empty state."""
    try:
        seen = json.loads(path.read_text(encoding="utf-8")).get("seen", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return {k: v for k, v in seen.items() if isinstance(v, str)} if isinstance(seen, dict) else {}


def prune_seen(seen: dict[str, str], now: datetime) -> dict[str, str]:
    """Drop the entries first seen more than SEEN_DAYS days ago, and the damaged ones."""
    kept = {}
    for key, first in seen.items():
        try:
            age = (now.date() - date.fromisoformat(first[:10])).days
        except ValueError:
            continue
        if age <= SEEN_DAYS:
            kept[key] = first
    return kept


def save_state(path: Path, seen: dict[str, str]) -> None:
    """Write the state atomically."""
    write_atomic(path, json.dumps({"seen": seen}, indent=2, sort_keys=True).encode("utf-8"))


# ---------------------------------------------------------------- command line


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    """The command line."""
    parser = argparse.ArgumentParser(description="Build the personal feed (docs/FEEDS.md).")
    parser.add_argument("--config", type=Path, help="feeds.toml (default $HERMES_HOME/feeds/feeds.toml)")
    parser.add_argument("--out", type=Path, help="output folder (default $HERMES_HOME/feeds/out)")
    parser.add_argument("--state", type=Path, help="state file (default $HERMES_HOME/feeds/state.json)")
    parser.add_argument("--dry-run", action="store_true", help="print the digest, write nothing")
    parser.add_argument("--no-state", action="store_true", help="write the outputs, ignore the state")
    parser.add_argument("--opml-only", action="store_true", help="write sources.opml and stop")
    parser.add_argument("--max-seconds", type=float, default=150.0, help="deadline for fetching")
    parser.add_argument("--source", nargs="+", action="extend", default=[], help="only these ids")
    return parser.parse_args(argv)


def resolve_paths(args: argparse.Namespace) -> tuple[Path, Paths]:
    """The configuration file and the output paths, with $HERMES_HOME defaults."""
    home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser() / "feeds"
    return args.config or home / "feeds.toml", Paths(args.out or home / "out", args.state or home / "state.json")


def emit_digest(chosen: Sequence[Item], report: Report) -> None:
    """The digest writer: stdout is what the cron job posts. No item, no output."""
    if chosen:
        print(render_digest(chosen, report.cfg, report.now, report.errors), end="")


def fresh_items(report: Report, seen: dict[str, str]) -> list[Item]:
    """The items above the digest threshold that the state has not seen."""
    threshold = report.cfg.output.digest_min_score
    return [i for i in report.items if i.score >= threshold and item_id(i.link) not in seen]


def publish(report: Report, args: argparse.Namespace, paths: Paths) -> None:
    """Write the outputs, print the new items above the digest threshold, update the state."""
    stateful = not (args.no_state or args.dry_run)
    seen = prune_seen(load_state(paths.state), report.now) if stateful else {}
    chosen = pick_digest(fresh_items(report, seen), report, report.cfg.output.digest_max_chars)
    if not args.dry_run:
        write_outputs(report, paths.out)
    emit_digest(chosen, report)
    if stateful:
        today = report.now.date().isoformat()
        save_state(paths.state, {**seen, **{item_id(i.link): today for i in chosen}})


def fail_run(report: Report, args: argparse.Namespace, paths: Paths) -> None:
    """No source worked: keep the old feed, write health.json, end with an error."""
    if not args.dry_run:
        write_atomic(paths.out / "health.json", build_health(report))
    failed = f" (errors: {', '.join(report.errors)})" if report.errors else ""
    raise FeedError(f"no source ran{failed}")


def build(args: argparse.Namespace, fetch: Fetch | None, now: datetime) -> None:
    """The whole run. Raise FeedError when no source worked."""
    config_path, paths = resolve_paths(args)
    cfg = load_config(config_path)
    sources = select_sources(cfg, args.source)
    if args.opml_only:
        write_atomic(paths.out / "sources.opml", build_opml(cfg, sources))
        return
    run = Run(cfg, fetch or Fetcher(), now, time.monotonic() + args.max_seconds)
    report = make_report(cfg, sources, collect(sources, run), now)
    if any(r.status == "ok" for r in report.results):
        publish(report, args, paths)
    else:
        fail_run(report, args, paths)


def main(argv: Sequence[str] | None = None, *, fetch: Fetch | None = None, now: datetime | None = None) -> int:
    """Exit 0 when one source worked. Exit 1 when none worked, or a write failed."""
    args = parse_args(argv)
    try:
        build(args, fetch, now or datetime.now(timezone.utc))
    except (FeedError, OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
