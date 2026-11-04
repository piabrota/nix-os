"""Offline tests of hermes/feeds/build_feed.py. No test opens a socket: the network is a function."""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import time
import tomllib
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
from io import BytesIO, StringIO
from pathlib import Path
from xml.etree import ElementTree as ET

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import build_feed as bf  # noqa: E402

NOW = datetime(2026, 11, 4, 12, 0, tzinfo=timezone.utc)
ATOM = "{http://www.w3.org/2005/Atom}"

RAW_CONFIG = {
    "title": "Test feed",
    "output": {"min_score": 4.0, "digest_items": 5, "digest_min_score": 6.0},
    "negative": {"terms": ["giveaway"]},
    "group": [{"id": "agents", "title": "Agents"}, {"id": "science", "title": "Science"}],
    "interest": [
        {"name": "Coding agents", "origin": "chat", "weight": 4, "terms": ["omp", "claude code"]},
        {"name": "Rust", "origin": "profile", "weight": 3, "terms": ["rust"]},
    ],
}
CFG = bf.parse_config(RAW_CONFIG)

RUN_CONFIG = """
title = "Test feed"
[output]
max_items = 10
digest_items = 5
digest_min_score = 6.0
[negative]
terms = ["giveaway"]
[[group]]
id = "agents"
title = "Agents"
[[group]]
id = "science"
title = "Science"
[[interest]]
name = "Coding agents"
origin = "chat"
weight = 4
terms = ["omp"]
[[interest]]
name = "Rust"
origin = "profile"
weight = 3
terms = ["rust"]
[[source]]
id = "rss"
group = "agents"
kind = "feed"
url = "https://example.org/rss.xml"
weight = 5
limit = 10
max_age_days = 30
[[source]]
id = "atom"
group = "science"
kind = "feed"
url = "https://example.org/atom.xml"
weight = 3
pinned = true
limit = 10
max_age_days = 60
[[source]]
id = "gh"
group = "agents"
kind = "github_search"
query = "topic:x created:>{d7}"
weight = 2
limit = 10
max_age_days = 14
"""


def fixture(name: str) -> bytes:
    return (HERE / "fixtures" / name).read_bytes()


def make_source(**fields) -> bf.Source:
    base = {
        "id": "s",
        "group": "agents",
        "kind": "feed",
        "weight": 3,
        "max_age_days": 21,
        "pinned_keep": 3,
        "url": "https://example.org/feed",
    }
    return bf.Source(**{**base, **fields})


def make_item(**fields) -> bf.Item:
    base = {
        "title": "T",
        "link": "https://example.org/a",
        "summary": "",
        "date": NOW,
        "dated": True,
        "source": "s",
        "group": "agents",
    }
    return bf.Item(**{**base, **fields})


def hours_ago(hours: float) -> datetime:
    return NOW - timedelta(hours=hours)


def http_error(code: int) -> urllib.error.HTTPError:
    error = urllib.error.HTTPError("https://example.org/", code, "x", {}, BytesIO())
    error.close()  # nothing reads the body; a closed error leaves no warning
    return error


class FakeFetch:
    """A network in a dict: the first key that starts the URL gives the answer."""

    def __init__(self, responses: dict[str, bytes | Exception]) -> None:
        self.responses = responses
        self.calls: list[str] = []

    def __call__(self, url: str, headers: dict[str, str]) -> bytes:
        self.calls.append(url)
        for prefix, answer in self.responses.items():
            if url.startswith(prefix):
                if isinstance(answer, Exception):
                    raise answer
                return answer
        raise AssertionError(f"unexpected URL {url}")


def good_responses() -> dict[str, bytes | Exception]:
    return {
        "https://example.org/rss.xml": fixture("rss.xml"),
        "https://example.org/atom.xml": fixture("atom.xml"),
        "https://api.github.com/": fixture("github.json"),
    }


class ParsingTest(unittest.TestCase):
    def test_rss(self) -> None:
        items = bf.parse_feed(fixture("rss.xml"), make_source(), NOW)
        self.assertEqual(
            [i.title for i in items],
            ["Oh-my-pi & omp: release notes", "A complicated story", "An item with no date"],
        )
        first = items[0]
        self.assertEqual(first.summary, "Short teaser & more.")
        self.assertEqual(first.date, datetime(2026, 11, 4, 6, 0, tzinfo=timezone.utc))
        self.assertEqual(items[1].summary, "The Rust port, in full.")
        self.assertEqual(items[1].date, datetime(2026, 11, 2, 12, 0, tzinfo=timezone.utc))

    def test_item_without_link_is_dropped_and_item_without_date_gets_run_time(self) -> None:
        items = bf.parse_feed(fixture("rss.xml"), make_source(), NOW)
        self.assertNotIn("An item with no link", [i.title for i in items])
        undated = items[-1]
        self.assertEqual((undated.date, undated.dated), (NOW, False))

    def test_atom(self) -> None:
        items = bf.parse_feed(fixture("atom.xml"), make_source(), NOW)
        self.assertEqual([i.title for i in items], ["v1.2.0", "v1.1.0"])
        self.assertEqual(items[0].link, "https://example.org/releases/v1.2.0")
        self.assertEqual(items[0].summary, "Fixes & adds Nix flake support.")
        self.assertEqual(items[1].date, datetime(2026, 10, 1, 6, 30, tzinfo=timezone.utc))
        self.assertEqual(items[1].summary, "Plain summary.")

    def test_cut_feed_keeps_complete_items(self) -> None:
        items = bf.parse_feed(fixture("podcast_cut.xml"), make_source(limit=6), NOW)
        self.assertEqual([i.title for i in items], ["Episode 3: omp in practice", "Episode 2", "Episode 1"])

    def test_limit_stops_early(self) -> None:
        items = bf.parse_feed(fixture("podcast_cut.xml"), make_source(limit=2), NOW)
        self.assertEqual(len(items), 2)

    def test_no_item_and_broken_xml_is_an_error(self) -> None:
        with self.assertRaises(ET.ParseError):
            bf.parse_feed(b"<html><body>Please wait", make_source(), NOW)

    def test_html_is_stripped(self) -> None:
        text = "<p>Tom &amp; <b>Jerry</b>&nbsp;said&#33;</p>\n\n<br/>  a &lt; b and c &gt; d"
        self.assertEqual(bf.clean_text(text), "Tom & Jerry said! a < b and c > d")

    def test_summary_is_cut_at_400(self) -> None:
        self.assertEqual(len(bf.summarize("<p>" + "word " * 200 + "</p>")), 399)

    def test_control_characters_are_removed(self) -> None:
        self.assertEqual(bf.clean_text("a\x00b\x1bc"), "abc")

    def test_dates(self) -> None:
        expected = datetime(2026, 11, 4, 9, 0, tzinfo=timezone.utc)
        self.assertEqual(bf.parse_date("Wed, 04 Nov 2026 06:00:00 -0300"), expected)
        self.assertEqual(bf.parse_date("2026-11-04T09:00:00Z"), expected)
        self.assertEqual(bf.parse_date("2026-11-04T11:00:00+02:00"), expected)
        self.assertEqual(bf.parse_date("2026-11-04T09:00:00"), expected)
        self.assertIsNone(bf.parse_date("yesterday"))
        self.assertIsNone(bf.parse_date(""))

    def test_github_items(self) -> None:
        src = make_source(kind="github_search", limit=10)
        items = bf.parse_github(fixture("github.json"), src, NOW)
        self.assertEqual([i.title for i in items], ["acme/omp-tools", "acme/quiet", "acme/big"])
        first = items[0]
        self.assertEqual(first.link, "https://github.com/acme/omp-tools")
        self.assertEqual((first.summary, first.stars), ("Tools for omp users", 99))
        self.assertEqual(first.date, datetime(2026, 11, 2, 8, 0, tzinfo=timezone.utc))
        self.assertEqual(items[1].summary, "")

    def test_github_query_dates(self) -> None:
        src = make_source(kind="github_search", query="topic:x created:>{d7} pushed:>{d14} a:>{d30}", limit=7)
        url = bf.github_url(src, NOW)
        self.assertTrue(url.startswith("https://api.github.com/search/repositories?"))
        params = dict(p.split("=", 1) for p in url.split("?", 1)[1].split("&"))
        decoded = {k: bf.urllib.parse.unquote_plus(v) for k, v in params.items()}
        self.assertEqual(decoded["q"], "topic:x created:>2026-10-28 pushed:>2026-10-21 a:>2026-10-05")
        self.assertEqual((decoded["sort"], decoded["order"], decoded["per_page"]), ("stars", "desc", "7"))

    def test_github_token_only_when_set(self) -> None:
        self.assertEqual(bf.github_headers({}), {"Accept": "application/vnd.github+json"})
        with_token = bf.github_headers({"GITHUB_TOKEN": "dummy"})
        self.assertEqual(with_token["Authorization"], "Bearer dummy")

    def test_apple_genre_filter(self) -> None:
        wanted = make_source(kind="apple_chart", genres=("Technology",), limit=100)
        items = bf.parse_apple(fixture("apple.json"), wanted, NOW)
        self.assertEqual([i.title for i in items], ["Agents Weekly"])
        self.assertEqual((items[0].dated, items[0].date), (False, NOW))
        self.assertEqual(items[0].summary, "Acme Labs. Technology, Podcasts")
        everything = bf.parse_apple(fixture("apple.json"), make_source(kind="apple_chart"), NOW)
        self.assertEqual(len(everything), 3)


class LinkTest(unittest.TestCase):
    def test_normalise_link(self) -> None:
        link = "https://Example.org/posts/omp-1/?utm_source=rss&id=7&UTM_medium=x#top"
        self.assertEqual(bf.normalise_link(link), "https://example.org/posts/omp-1?id=7")
        self.assertEqual(bf.normalise_link("https://example.org/"), "https://example.org")

    def test_item_id_is_stable_across_link_variants(self) -> None:
        a = bf.item_id("https://Example.org/a/?utm_source=x#frag")
        self.assertEqual(a, bf.item_id("https://example.org/a"))
        self.assertEqual(len(a), 16)

    def test_dedupe_by_link_keeps_highest_score(self) -> None:
        low = make_item(link="https://example.org/a/?utm_source=x", title="Low", score=5.0)
        high = make_item(link="https://EXAMPLE.org/a", title="High", score=7.0)
        other = make_item(link="https://example.org/b", title="Other", score=1.0)
        self.assertEqual({i.title for i in bf.dedupe([low, high, other])}, {"High", "Other"})

    def test_dedupe_by_title(self) -> None:
        a = make_item(link="https://a.example/1", title="Release: v2.0!", score=4.0)
        b = make_item(link="https://b.example/2", title="release v2 0", score=6.0)
        self.assertEqual([i.score for i in bf.dedupe([a, b])], [6.0])


class ScoringTest(unittest.TestCase):
    def test_word_boundaries(self) -> None:
        interest = CFG.interests[0]
        self.assertGreater(bf.interest_points(interest, make_item(title="Oh-my-pi and omp")), 0)
        self.assertGreater(bf.interest_points(interest, make_item(title="OMP, again")), 0)
        self.assertGreater(bf.interest_points(interest, make_item(title="Claude  Code".replace("  ", " "))), 0)
        self.assertEqual(bf.interest_points(interest, make_item(title="A complicated story")), 0)
        self.assertEqual(bf.interest_points(interest, make_item(title="Tromp", summary="pomp")), 0)

    def test_title_beats_summary_and_counts_once(self) -> None:
        interest = CFG.interests[0]
        both = make_item(title="omp omp", summary="omp")
        self.assertAlmostEqual(bf.interest_points(interest, both), 4.8)
        self.assertAlmostEqual(bf.interest_points(interest, make_item(summary="omp")), 1.6)

    def test_interest_sum_is_capped(self) -> None:
        raw = {**RAW_CONFIG, "interest": [
            {"name": "A", "origin": "chat", "weight": 5, "terms": ["alpha"]},
            {"name": "B", "origin": "chat", "weight": 5, "terms": ["beta"]},
        ]}
        cfg = bf.parse_config(raw)
        points, names = bf.interest_score(make_item(title="alpha beta"), cfg.interests)
        self.assertEqual((points, names), (8.0, ["A", "B"]))

    def test_exact_score_of_one_item(self) -> None:
        # base 3 + title "omp" (3 * 4 / 5 * 2 = 4.8) + summary "rust" (1 * 3 / 5 * 2 = 1.2) + recency 2.0
        item = make_item(title="Fixing the omp loop", summary="Written in Rust", date=hours_ago(12))
        scored = bf.score_item(item, make_source(weight=3, max_age_days=10), CFG, NOW)
        self.assertEqual(scored.score, 11.0)
        self.assertEqual(scored.matched, ("Coding agents", "Rust"))

    def test_score_of_a_github_item_has_a_stars_bonus(self) -> None:
        src = make_source(kind="github_search", weight=2, max_age_days=10)
        item = make_item(title="acme/tool", date=hours_ago(48), stars=99)
        scored = bf.score_item(item, src, CFG, NOW)
        # recency at 2 days of 10: 2 * (1 - 1 / 9) = 1.78; stars: log10(100) / 1.5 = 1.33
        self.assertEqual(scored.score, 5.1)
        self.assertEqual(bf.stars_bonus(10**9), 3.0)
        self.assertEqual(bf.stars_bonus(0), 0.0)

    def test_recency_bonus(self) -> None:
        src = make_source(max_age_days=21)
        bonus = lambda item: bf.recency_bonus(item, src, NOW)  # noqa: E731
        self.assertEqual(bonus(make_item(date=NOW)), 2.0)
        self.assertEqual(bonus(make_item(date=hours_ago(24))), 2.0)
        self.assertEqual(bonus(make_item(date=NOW - timedelta(days=11))), 1.0)
        self.assertEqual(bonus(make_item(date=NOW - timedelta(days=21))), 0.0)
        self.assertEqual(bonus(make_item(date=NOW, dated=False)), 0.0)

    def test_negative_term_drops_in_title_and_summary(self) -> None:
        src = make_source(weight=5)
        self.assertIsNone(bf.score_item(make_item(title="Free GIVEAWAY of omp"), src, CFG, NOW))
        self.assertIsNone(bf.score_item(make_item(title="omp", summary="a giveaway"), src, CFG, NOW))
        self.assertIsNotNone(bf.score_item(make_item(title="omp"), src, CFG, NOW))

    def test_requires_match(self) -> None:
        src = make_source(weight=5, requires_match=True)
        items = [make_item(title="About omp", link="https://x/1"), make_item(title="Nothing", link="https://x/2")]
        kept = bf.select_items(src, items, CFG, NOW)
        self.assertEqual([i.title for i in kept], ["About omp"])
        open_src = make_source(weight=5)
        self.assertEqual(len(bf.select_items(open_src, items, CFG, NOW)), 2)

    def test_min_score(self) -> None:
        weak = make_item(title="Nothing", date=NOW - timedelta(days=20))
        self.assertEqual(bf.select_items(make_source(weight=1), [weak], CFG, NOW), [])
        self.assertEqual(len(bf.select_items(make_source(weight=4), [weak], CFG, NOW)), 1)

    def test_max_age_days(self) -> None:
        src = make_source(weight=5, max_age_days=5)
        items = [
            make_item(link="https://x/new", date=NOW - timedelta(days=4)),
            make_item(link="https://x/old", date=NOW - timedelta(days=6)),
            make_item(link="https://x/undated", dated=False),
        ]
        kept = {i.link for i in bf.select_items(src, items, CFG, NOW)}
        self.assertEqual(kept, {"https://x/new", "https://x/undated"})

    def test_pinned_keeps_the_newest_whatever_the_score(self) -> None:
        items = [make_item(link=f"https://x/{d}", date=NOW - timedelta(days=d)) for d in (1, 2, 4, 5)]
        pinned = make_source(weight=1, pinned=True, pinned_keep=2, max_age_days=10)
        kept = bf.select_items(pinned, items, CFG, NOW)
        self.assertEqual({i.link for i in kept}, {"https://x/1", "https://x/2"})
        self.assertEqual(bf.select_items(make_source(weight=1, max_age_days=10), items, CFG, NOW), [])

    def test_pinned_items_older_than_max_age_are_dropped(self) -> None:
        items = [make_item(link=f"https://x/{d}", date=NOW - timedelta(days=d)) for d in (1, 4, 5)]
        src = make_source(weight=1, pinned=True, pinned_keep=3, max_age_days=3)
        self.assertEqual([i.link for i in bf.select_items(src, items, CFG, NOW)], ["https://x/1"])

    def test_rank_orders_by_score_then_date(self) -> None:
        a = make_item(link="https://x/a", score=5.0, date=hours_ago(5))
        b = make_item(link="https://x/b", score=5.0, date=hours_ago(1))
        c = make_item(link="https://x/c", score=9.0, date=hours_ago(50))
        self.assertEqual([i.link[-1] for i in bf.rank([a, b, c])], ["c", "b", "a"])


class OutputTest(unittest.TestCase):
    def report(self, items: list[bf.Item], now: datetime = NOW, errors: tuple[str, ...] = ()) -> bf.Report:
        return bf.Report(CFG, [], [], items, errors, now)

    def scored_items(self) -> list[bf.Item]:
        return [
            make_item(title="First & <best>", link="https://x/1?a=1&b=2", score=8.4, matched=("Rust",)),
            make_item(title="Second", link="https://x/2", score=6.0, group="science", source="arxiv"),
        ]

    def test_atom_parses_and_every_entry_is_complete(self) -> None:
        root = ET.fromstring(bf.build_atom(self.report(self.scored_items())))
        self.assertEqual(root.tag, ATOM + "feed")
        for parent in [root, *root.findall(ATOM + "entry")]:
            for name in ("id", "title", "updated"):
                self.assertTrue((parent.findtext(ATOM + name) or "").strip(), name)
        self.assertEqual(root.findtext(ATOM + "id"), "tag:piabrota.art,2026:feed:personal")
        self.assertEqual(root.findtext(ATOM + "updated"), "2026-11-04T12:00:00Z")
        first = root.findall(ATOM + "entry")[0]
        self.assertEqual(first.findtext(ATOM + "title"), "[agents] First & <best>")
        self.assertEqual(first.find(ATOM + "link").attrib, {"rel": "alternate", "href": "https://x/1?a=1&b=2"})
        self.assertEqual(first.find(ATOM + "summary").attrib, {"type": "text"})
        self.assertEqual(first.findtext(ATOM + "summary"), "score 8.4 - s - Rust\n")
        self.assertEqual([c.get("term") for c in first.findall(ATOM + "category")], ["agents", "Rust"])

    def test_atom_entry_ids_are_stable_between_runs(self) -> None:
        def ids(now: datetime) -> list[str]:
            root = ET.fromstring(bf.build_atom(self.report(self.scored_items(), now)))
            return [e.findtext(ATOM + "id") for e in root.findall(ATOM + "entry")]

        self.assertEqual(ids(NOW), ids(NOW + timedelta(hours=3)))
        self.assertTrue(all(i.startswith("tag:piabrota.art,2026:item:") for i in ids(NOW)))

    def test_atom_without_items_is_valid(self) -> None:
        root = ET.fromstring(bf.build_atom(self.report([])))
        self.assertEqual(root.findall(ATOM + "entry"), [])

    def test_digest_format_and_groups(self) -> None:
        item = make_item(title="A_b *c* [d]", link="https://x/1", score=8.4, source="src", date=NOW - timedelta(days=2))
        later = make_item(title="Sci", link="https://x/2", score=6.0, group="science", date=hours_ago(5))
        text = bf.render_digest([later, item], CFG, NOW, ())
        self.assertEqual(
            text.splitlines(),
            [
                "# Digest 2026-11-04",
                "",
                "## Agents",
                "- **8.4** A\\_b \\*c\\* \\[d\\] - src, 2d",
                "  <https://x/1>",
                "",
                "## Science",
                "- **6.0** Sci - s, 5h",
                "  <https://x/2>",
            ],
        )

    def test_digest_date_is_the_date_in_sao_paulo(self) -> None:
        late = datetime(2026, 11, 5, 1, 0, tzinfo=timezone.utc)
        self.assertEqual(bf.render_digest([], CFG, late, ()).splitlines()[0], "# Digest 2026-11-04")

    def test_digest_error_line(self) -> None:
        text = bf.render_digest([], CFG, NOW, ("bad", "worse"))
        self.assertEqual(text.splitlines()[-1], "Sources with errors: bad, worse")

    def test_digest_is_cut_in_whole_items(self) -> None:
        items = [
            make_item(title=f"Item {n} " + "x" * 200, link=f"https://x/{n}", score=9.0 - n / 10)
            for n in range(5)
        ]
        report = self.report(items, errors=("bad",))
        chosen = bf.pick_digest(items, report, 700)
        text = bf.render_digest(chosen, CFG, NOW, ("bad",))
        self.assertLessEqual(len(text), 700)
        self.assertEqual(chosen, items[: len(chosen)])
        self.assertTrue(0 < len(chosen) < 5)
        self.assertEqual(text.count("- **"), len(chosen))
        self.assertEqual(text.count("  <https://"), len(chosen))
        self.assertTrue(text.endswith("Sources with errors: bad\n"))

    def test_digest_item_limit(self) -> None:
        items = [make_item(link=f"https://x/{n}", score=9.0) for n in range(9)]
        self.assertEqual(len(bf.pick_digest(items, self.report(items))), 5)

    def test_opml(self) -> None:
        raw = {**RAW_CONFIG, "source": [
            {"id": "f1", "group": "agents", "kind": "feed", "weight": 3, "url": "https://x/a?q=1&r=2"},
            {"id": "g1", "group": "agents", "kind": "github_search", "weight": 3, "query": "topic:x"},
            {"id": "c1", "group": "science", "kind": "apple_chart", "weight": 3, "url": "https://x/chart"},
        ]}
        cfg = bf.parse_config(raw)
        root = ET.fromstring(bf.build_opml(cfg, cfg.sources))
        self.assertEqual(root.get("version"), "2.0")
        groups = root.find("body").findall("outline")
        self.assertEqual([g.get("text") for g in groups], ["Agents"])
        feeds = groups[0].findall("outline")
        self.assertEqual([(f.get("type"), f.get("text"), f.get("xmlUrl")) for f in feeds], [("rss", "f1", "https://x/a?q=1&r=2")])

    def test_prune_seen(self) -> None:
        old = (NOW - timedelta(days=61)).date().isoformat()
        edge = (NOW - timedelta(days=60)).date().isoformat()
        seen = {"old": old, "edge": edge, "bad": "x"}
        self.assertEqual(bf.prune_seen(seen, NOW), {"edge": edge})


class FetchTest(unittest.TestCase):
    def test_retry_once_on_timeout_and_5xx(self) -> None:
        for failure in (TimeoutError(), http_error(503)):
            calls: list[int] = []
            sleeps: list[float] = []

            def do() -> bytes:
                calls.append(1)
                if len(calls) == 1:
                    raise failure
                return b"ok"

            self.assertEqual(bf.get_with_retry(do, sleeps.append), b"ok")
            self.assertEqual((len(calls), sleeps), (2, [2.0]))

    def test_second_failure_is_raised(self) -> None:
        def do() -> bytes:
            raise TimeoutError()

        with self.assertRaises(TimeoutError):
            bf.get_with_retry(do, lambda _: None)

    def test_no_retry_on_4xx(self) -> None:
        for code in (403, 404, 429):
            calls: list[int] = []

            def do() -> bytes:
                calls.append(1)
                raise http_error(code)

            with self.assertRaises(urllib.error.HTTPError):
                bf.get_with_retry(do, lambda _: None)
            self.assertEqual(len(calls), 1)

    def test_one_request_per_host_at_a_time(self) -> None:
        class Probe(bf.Fetcher):
            active = 0
            peak = 0
            guard = threading.Lock()

            def _open(self, url: str, headers: dict[str, str]) -> bytes:
                with self.guard:
                    self.active += 1
                    self.peak = max(self.peak, self.active)
                time.sleep(0.01)
                with self.guard:
                    self.active -= 1
                return b""

        probe = Probe()
        threads = [threading.Thread(target=probe, args=("https://same.example/x", {})) for _ in range(6)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(probe.peak, 1)

    def test_gap_between_github_queries(self) -> None:
        class Quiet(bf.Fetcher):
            def _open(self, url: str, headers: dict[str, str]) -> bytes:
                return b"{}"

        sleeps: list[float] = []
        fetcher = Quiet(sleep=sleeps.append, clock=lambda: 100.0)
        fetcher("https://api.github.com/a", {})
        self.assertEqual(sleeps, [])
        fetcher("https://api.github.com/b", {})
        self.assertEqual(sleeps, [7.0])
        fetcher("https://example.org/", {})
        fetcher("https://example.org/", {})
        self.assertEqual(sleeps, [7.0])


class RunTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name)
        self.config = self.dir / "feeds.toml"
        self.config.write_text(RUN_CONFIG, encoding="utf-8")
        self.out = self.dir / "out"
        self.state = self.dir / "state.json"

    def run_main(self, *extra: str, responses: dict | None = None) -> tuple[int, str, str, FakeFetch]:
        fake = FakeFetch(responses if responses is not None else good_responses())
        argv = ["--config", str(self.config), "--out", str(self.out), "--state", str(self.state), *extra]
        with redirect_stdout(StringIO()) as stdout, redirect_stderr(StringIO()) as stderr:
            code = bf.main(argv, fetch=fake, now=NOW)
        return code, stdout.getvalue(), stderr.getvalue(), fake

    def entries(self) -> list[ET.Element]:
        return ET.parse(self.out / "feed.atom").getroot().findall(ATOM + "entry")

    def test_first_run_writes_all_outputs_and_prints_the_best(self) -> None:
        code, stdout, stderr, _ = self.run_main()
        self.assertEqual((code, stderr), (0, ""))
        self.assertTrue(stdout.startswith("# Digest 2026-11-04\n"))
        self.assertIn("Oh-my-pi & omp: release notes", stdout.replace("\\", ""))
        self.assertLessEqual(len(stdout), 1900)
        for name in ("feed.atom", "digest.md", "sources.opml", "health.json"):
            self.assertTrue((self.out / name).is_file(), name)
        self.assertEqual(list(self.out.glob(".*")), [])
        self.assertTrue(self.state.is_file())

    def test_pinned_source_keeps_a_low_score(self) -> None:
        self.run_main()
        titles = [e.findtext(ATOM + "title") for e in self.entries()]
        self.assertIn("[science] v1.1.0", titles)

    def test_second_run_prints_nothing_and_the_feed_keeps_its_items(self) -> None:
        _, first, _, _ = self.run_main()
        count = len(self.entries())
        code, second, _, _ = self.run_main()
        self.assertTrue(first)
        self.assertEqual((code, second), (0, ""))
        self.assertEqual(len(self.entries()), count)

    def test_state_holds_the_printed_items_only(self) -> None:
        self.run_main()
        seen = json.loads(self.state.read_text(encoding="utf-8"))["seen"]
        self.assertEqual(set(seen.values()), {"2026-11-04"})
        self.assertEqual(seen[bf.item_id("https://example.org/posts/omp-1?id=7")], "2026-11-04")
        self.assertNotIn(bf.item_id("https://example.org/releases/v1.1.0"), seen)

    def test_no_state_ignores_and_keeps_the_state(self) -> None:
        self.run_main()
        before = self.state.read_text(encoding="utf-8")
        code, stdout, _, _ = self.run_main("--no-state")
        self.assertEqual(code, 0)
        self.assertTrue(stdout)
        self.assertEqual(self.state.read_text(encoding="utf-8"), before)

    def test_dry_run_writes_no_file(self) -> None:
        code, stdout, _, _ = self.run_main("--dry-run")
        self.assertEqual(code, 0)
        self.assertTrue(stdout)
        self.assertFalse(self.out.exists())
        self.assertFalse(self.state.exists())

    def test_failing_source_goes_to_health_and_the_run_exits_0(self) -> None:
        responses = good_responses()
        responses["https://example.org/atom.xml"] = http_error(429)
        code, stdout, _, _ = self.run_main(responses=responses)
        self.assertEqual(code, 0)
        self.assertEqual(stdout.splitlines()[-1], "Sources with errors: atom")
        health = json.loads((self.out / "health.json").read_text(encoding="utf-8"))["sources"]
        self.assertEqual((health["atom"]["status"], health["atom"]["error"]), ("error", "HTTP 429"))
        self.assertEqual(health["rss"]["status"], "ok")
        self.assertEqual(health["rss"]["items"], 3)
        self.assertEqual(health["rss"]["newest"], "2026-11-04T06:00:00Z")

    def test_unparsable_source_is_an_error_not_a_crash(self) -> None:
        responses = good_responses()
        responses["https://example.org/atom.xml"] = b"<html>blocked"
        code, _, _, _ = self.run_main(responses=responses)
        self.assertEqual(code, 0)
        health = json.loads((self.out / "health.json").read_text(encoding="utf-8"))["sources"]
        self.assertEqual(health["atom"]["status"], "error")

    def test_every_source_failing_exits_1_and_keeps_the_old_feed(self) -> None:
        self.run_main()
        old = (self.out / "feed.atom").read_bytes()
        down = urllib.error.URLError("down")
        responses = {"https://": down}
        code, stdout, stderr, _ = self.run_main(responses=responses)
        self.assertEqual((code, stdout), (1, ""))
        self.assertIn("no source ran", stderr)
        self.assertEqual((self.out / "feed.atom").read_bytes(), old)
        health = json.loads((self.out / "health.json").read_text(encoding="utf-8"))["sources"]
        self.assertEqual({h["status"] for h in health.values()}, {"error"})

    def test_deadline_skips_sources_not_started(self) -> None:
        code, _, stderr, fake = self.run_main("--max-seconds", "0")
        self.assertEqual((code, fake.calls), (1, []))
        self.assertIn("no source ran", stderr)
        health = json.loads((self.out / "health.json").read_text(encoding="utf-8"))["sources"]
        self.assertEqual({h["status"] for h in health.values()}, {"skipped"})

    def test_unknown_source_id_runs_nothing(self) -> None:
        code, stdout, stderr, fake = self.run_main("--dry-run", "--source", "does-not-exist")
        self.assertEqual((code, stdout, fake.calls), (1, "", []))
        self.assertIn("no source ran", stderr)

    def test_source_option_limits_the_run(self) -> None:
        code, _, _, fake = self.run_main("--source", "rss")
        self.assertEqual((code, fake.calls), (0, ["https://example.org/rss.xml"]))

    def test_github_source_asks_the_dated_query(self) -> None:
        _, _, _, fake = self.run_main("--source", "gh")
        self.assertEqual(len(fake.calls), 1)
        self.assertIn("created%3A%3E2026-10-28", fake.calls[0])

    def test_opml_only_writes_the_opml_and_asks_no_network(self) -> None:
        code, stdout, _, fake = self.run_main("--opml-only")
        self.assertEqual((code, stdout, fake.calls), (0, "", []))
        root = ET.parse(self.out / "sources.opml").getroot()
        outlines = root.findall(".//outline[@type]")
        self.assertEqual({o.get("text") for o in outlines}, {"rss", "atom"})
        self.assertEqual({p.name for p in self.out.iterdir()}, {"sources.opml"})

    def test_write_failure_exits_1(self) -> None:
        self.out.write_text("a file, not a folder", encoding="utf-8")
        code, _, stderr, _ = self.run_main()
        self.assertEqual(code, 1)
        self.assertTrue(stderr.startswith("error:"))


class RealConfigTest(unittest.TestCase):
    def setUp(self) -> None:
        with (HERE.parent / "feeds.toml").open("rb") as handle:
            self.raw = tomllib.load(handle)

    def test_sources(self) -> None:
        sources = self.raw["source"]
        ids = [s["id"] for s in sources]
        groups = {g["id"] for g in self.raw["group"]}
        self.assertEqual(len(ids), len(set(ids)))
        for source in sources:
            for key in ("id", "group", "kind", "weight"):
                self.assertIn(key, source, source.get("id"))
            self.assertIn(source["group"], groups, source["id"])
            self.assertIn(source["kind"], bf.KINDS, source["id"])
            self.assertIn(source["weight"], range(1, 6), source["id"])

    def test_interests(self) -> None:
        for interest in self.raw["interest"]:
            self.assertTrue(interest["name"])
            self.assertIn(interest["origin"], {"chat", "profile"}, interest["name"])
            self.assertIn(interest["weight"], range(1, 6), interest["name"])
            self.assertTrue(interest["terms"], interest["name"])

    def test_the_script_loads_it(self) -> None:
        cfg = bf.load_config(HERE.parent / "feeds.toml")
        self.assertEqual(len(cfg.sources), len(self.raw["source"]))
        self.assertEqual(len(cfg.interests), len(self.raw["interest"]))


if __name__ == "__main__":
    unittest.main()
