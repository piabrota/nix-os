"""Tests of the pirsig-notes and pirsig-videos plugins, with the standard library and git only.

Each plugin is assembled as hermes.nix does it (its directory plus common/brain.py) in a temporary
directory, then imported as a package. `gh` is a stub; the brain is a local bare repository.
"""

import importlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
BUILD = Path(tempfile.mkdtemp(prefix="hermes-plugins-"))
for name, alias in (("pirsig-notes", "pnotes"), ("pirsig-videos", "pvideos")):
    shutil.copytree(HERE / name, BUILD / alias, copy_function=shutil.copyfile)
    os.chmod(BUILD / alias, 0o755)  # the Nix store's copy is read-only
    shutil.copyfile(HERE / "common" / "brain.py", BUILD / alias / "brain.py")
sys.path.insert(0, str(BUILD))
notes = importlib.import_module("pnotes.tools")
videos = importlib.import_module("pvideos.tools")
brain = importlib.import_module("pnotes.brain")

NOTE_10 = """---
pirsig: note
zid: "10"
title: "Repo: awesome-ocean-science"
kind: literature
---

# Repo: awesome-ocean-science

An index of ocean data.
"""


def git(*args, cwd=None):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


class Fixture(unittest.TestCase):
    """A bare `origin` with brain/Zettelkasten/10 ... .md on main, and a stub gh on PATH."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        os.environ["HERMES_HOME"] = str(self.tmp / "home")
        for k, v in {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
                     "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}.items():
            os.environ[k] = v
        self.origin = self.tmp / "origin.git"
        git("init", "--quiet", "--bare", "-b", "main", str(self.origin))
        seed = self.tmp / "seed"
        (seed / "brain" / "Zettelkasten").mkdir(parents=True)
        (seed / "brain" / "Zettelkasten" / "10 Repo awesome-ocean-science.md").write_text(NOTE_10)
        (seed / ".claude" / "agents").mkdir(parents=True)
        (seed / ".claude" / "agents" / "video-indexer.md").write_text("policy\n")
        (seed / "src").mkdir()
        (seed / "src" / "main.rs").write_text("fn main() {}\n")
        git("init", "--quiet", "-b", "main", cwd=seed)
        git("add", ".", cwd=seed)
        git("commit", "--quiet", "-m", "seed", cwd=seed)
        git("push", "--quiet", str(self.origin), "main", cwd=seed)
        bin_dir = self.tmp / "bin"
        bin_dir.mkdir()
        self.gh_log = self.tmp / "gh.log"
        (bin_dir / "gh").write_text(
            f"#!/bin/sh\nprintf '%s\\n' \"$@\" >> {self.gh_log}\n"
            "echo https://github.com/piabrota/pirsig/pull/1\n")
        (bin_dir / "gh").chmod(0o755)
        self.path = os.environ["PATH"]
        os.environ["PATH"] = f"{bin_dir}:{self.path}"
        brain.Brain.url = property(lambda b: str(self.origin))
        for mod in (notes, videos):
            mod.Brain.url = brain.Brain.url

    def tearDown(self):
        os.environ["PATH"] = self.path
        shutil.rmtree(self.tmp, ignore_errors=True)

    def origin_files(self, branch):
        out = subprocess.run(["git", "--git-dir", str(self.origin), "ls-tree", "-r", "--name-only", branch],
                             capture_output=True, text=True, check=True).stdout
        return out.split()

    def origin_show(self, branch, path):
        return subprocess.run(["git", "--git-dir", str(self.origin), "show", f"{branch}:{path}"],
                              capture_output=True, text=True, check=True).stdout


def note(**over):
    n = {"title": "Links beat folders", "type": "fleeting", "status": "unverified",
         "body": "Uma nota ligada volta a aparecer quando outra ideia chama por ela.",
         "links": [{"target": "10 Repo awesome-ocean-science", "why": "an example of an index"}]}
    n.update(over)
    return n


class NotesRules(unittest.TestCase):
    existing = {"10 Repo awesome-ocean-science"}

    def test_a_good_note_passes(self):
        self.assertEqual(notes.validate([note()], self.existing), [])

    def test_the_rules(self):
        cases = {
            "approved is the owner's word": note(status="approved"),
            "needs its source": note(type="literature"),
            "no note in the brain": note(links=[{"target": "nothing", "why": "x"}]),
            "has no reason": note(links=[{"target": "10 Repo awesome-ocean-science", "why": ""}]),
            "no link": note(links=[]),
            "email": note(body="Fale com joao@example.com."),
            "lowercase-with-hyphens": note(tags=["Big Tag"]),
            "more than one idea": note(body="palavra " * 501),
        }
        for expected, n in cases.items():
            with self.subTest(expected):
                self.assertTrue(any(expected in p for p in notes.validate([n], self.existing)),
                                notes.validate([n], self.existing))

    def test_links_inside_one_call_and_proposed(self):
        batch = [note(title="A", links=[{"target": "B", "why": "B explains A"}]),
                 note(title="B", links=[], proposed_link="a note on Luhmann's box")]
        self.assertEqual(notes.validate(batch, self.existing), [])
        self.assertTrue(notes.validate([note(title="A"), note(title="a")], self.existing))

    def test_files(self):
        now = datetime(2026, 11, 3, 22, 0, tzinfo=timezone.utc)
        batch = [note(title="Notas ligadas voltam", tags=["pkm"],
                      links=[{"target": "Uma ideia, uma nota", "why": "a mesma regra"}]),
                 note(title="Uma ideia, uma nota", proposed_link="uma nota sobre Luhmann")]
        files = notes.build(batch, {"10 Repo awesome-ocean-science": "Repo: awesome-ocean-science"}, now)
        self.assertEqual(list(files), ["brain/Inbox/202611032200-notas-ligadas-voltam.md",
                                       "brain/Inbox/202611032201-uma-ideia-uma-nota.md"])
        first, second = files.values()
        self.assertIn('id: "202611032200"\ntitle: "Notas ligadas voltam"\nkind: fleeting\n', first)
        self.assertIn('tags: ["pkm", "status/unverified", "hermes"]', first)
        self.assertNotIn("pirsig:", first)
        self.assertIn("- [[202611032201-uma-ideia-uma-nota]] Uma ideia, uma nota: a mesma regra", first)
        self.assertIn("- [[10 Repo awesome-ocean-science]] Repo: awesome-ocean-science: an example", second)
        self.assertIn("⚠ uma nota sobre Luhmann", second)

    def test_batch_size(self):
        for batch in ([], "not a list", [note()] * 21):
            with self.subTest(batch=str(batch)[:20]):
                self.assertEqual(notes.validate(batch, self.existing), ["give 1 to 20 notes"])

    def test_same_title_in_one_call(self):
        self.assertEqual(notes.validate([note(title="A"), note(title="a")], self.existing),
                         ["two notes have the same title: one idea, one note"])

    def test_title_length_and_literature_source(self):
        self.assertEqual(notes.validate([note(title="a" * 160)], self.existing), [])
        self.assertEqual(notes.validate([note(type="literature", source="Autor, 2020")], self.existing), [])
        for title in ("a" * 161, ""):
            with self.subTest(len(title)):
                self.assertEqual(notes.validate([note(title=title)], self.existing),
                                 ["note 1: the title is one line of at most 160 characters"])

    def test_word_limit_and_emails(self):
        self.assertEqual(notes.validate([note(body="palavra " * 501)], self.existing),
                         ["note 1: 501 words; more than 500 is more than one idea"])
        self.assertEqual(notes.validate([note(title="a@b.co", body="c@d.co e")], self.existing),
                         ["note 1: an email address; people appear by nickname only"] * 2)

    def test_every_rule_in_order_with_the_note_number(self):
        bad = note(title="x\ny", type="poem", status="approved", body="", source="a@b.co", tags=["Big"],
                   links=[{"target": "x\ny", "why": ""}])
        self.assertEqual(notes.validate([note(title="Ok"), bad], self.existing), [
            "note 2: the title is one line of at most 160 characters",
            "note 2: type is one of fleeting, literature, permanent",
            "note 2: status is one of unverified, partial, verified, open-question "
            "(approved is the owner's word)",
            "note 2: no body",
            "note 2: an email address; people appear by nickname only",
            "note 2: tag 'Big' is not lowercase-with-hyphens",
            "note 2: the link to 'x\\ny' has no reason",
            "note 2: links to itself",
        ])


class NotesPullRequest(Fixture):
    def test_search(self):
        out = json.loads(notes.search({"query": "ocean"}))
        self.assertEqual(out["matches"][0]["zid"], "10")
        self.assertEqual(out["matches"][0]["stem"], "10 Repo awesome-ocean-science")

    def test_submit_pushes_a_hermes_branch_and_opens_a_pr(self):
        out = json.loads(notes.submit({"request": "The owner asked to save one idea.", "notes": [note()]}))
        self.assertNotIn("error", out, out)
        self.assertEqual(out["branch"], "hermes/notes-links-beat-folders")
        self.assertEqual(out["pr"], "https://github.com/piabrota/pirsig/pull/1")
        files = self.origin_files(out["branch"])
        self.assertIn(out["files"][0], files)
        self.assertIn("src/main.rs", files, "the sparse checkout must not drop files from the commit")
        log = self.gh_log.read_text().split("\n")
        self.assertEqual(log[:2], ["pr", "create"])
        self.assertIn("hermes/notes-links-beat-folders", log)
        # the same idea again gets a branch of its own
        again = json.loads(notes.submit({"request": "Again.", "notes": [note()]}))
        self.assertEqual(again["branch"], "hermes/notes-links-beat-folders-2")

    def test_submit_refuses_broken_notes(self):
        out = json.loads(notes.submit({"request": "x", "notes": [note(status="approved")]}))
        self.assertIn("problems", out)
        self.assertFalse(self.gh_log.exists())

    def test_open_pr_stays_in_brain(self):
        b = notes.brain()
        for bad in ("src/evil.rs", "brain/../src/main.rs", "brain/Zettelkasten/10 Repo awesome-ocean-science.md"):
            with self.subTest(bad), self.assertRaises(brain.BrainError):
                b.open_pr({bad: "x"}, "x", "t", "b")

    def test_open_pr_needs_files_and_takes_bytes(self):
        b = notes.brain()
        with self.assertRaisesRegex(brain.BrainError, "nothing to submit"):
            b.open_pr({}, "x", "t", "b")
        out = b.open_pr({"brain/Inbox/x.bin": b"\x00\x01"}, "bin", "t", "b")
        self.assertIn("brain/Inbox/x.bin", self.origin_files(out["branch"]))

    def test_both_plugins_read_repo_and_base_from_the_config(self):
        class Ctx:
            def get_config(self, key, default):
                return {"repo": "a/b", "base": "dev"}.get(key, default)

        for mod in (notes, videos):
            with self.subTest(mod.PLUGIN):
                b = mod.brain(Ctx())
                self.assertEqual((b.repo, b.base), ("a/b", "dev"))
                self.assertEqual((mod.brain().repo, mod.brain().base), ("piabrota/pirsig", "main"))


LEITURA = """# Uma leitura

## Como ler este texto
O texto relata o que o autor diz.

## Parte 1: Começo
### [k=abertura t=00:00-01:00] O autor abre o vídeo
-> fim: o fim responde à abertura

O autor apresenta o tema.

![fig](mapa)

### [k=fim t=00:50-02:00] O autor fecha o vídeo
-> #10: o índice de dados do oceano

O autor resume.

## O que não foi checado
Nada.
"""

FIGURES = {"mapa": {f: "x" for f in videos.FIGURE_FIELDS}}


class Videos(Fixture):
    def folder(self, leitura=LEITURA, figures=FIGURES, duration=120):
        name = "2026-11-03-uma-leitura"
        d = videos.work_dir(name)
        (d / "figuras").mkdir(parents=True)
        (d / "video.json").write_text(json.dumps({
            "id": "abc", "url": "https://www.youtube.com/watch?v=abc", "title": "Uma leitura",
            "duration": duration, "captions": "pt-orig", "captions_kind": "automatic"}))
        (d / "leitura.markdown").write_text(leitura)
        (d / "figuras.json").write_text(json.dumps(figures))
        (d / "figuras" / "mapa.json").write_text("{}")
        (d / "transcript.txt").write_text("[00:00:00] olá\n")
        return name, d

    def test_captions_choice(self):
        info = {"language": "pt-BR", "subtitles": {"en": [], "pt-BR": [], "live_chat": []},
                "automatic_captions": {"pt-orig": []}}
        self.assertEqual(videos.pick_captions(info), ("pt-BR", True))
        self.assertEqual(videos.pick_captions({"language": "pt", "automatic_captions":
                                               {"en-orig": [], "pt-orig": []}}), ("pt-orig", False))
        self.assertEqual(videos.pick_captions({"language": "pt"}), (None, False))

    def test_transcript_blocks_of_30_s(self):
        events = [{"tStartMs": 1000, "segs": [{"utf8": "olá"}]},
                  {"tStartMs": 29000, "segs": [{"utf8": " mundo\n"}]},
                  {"tStartMs": 31000, "segs": [{"utf8": "depois"}]}, {"tStartMs": 40000}]
        self.assertEqual(videos.transcript(events), "[00:00:00] olá mundo\n[00:00:30] depois\n")

    def test_a_good_folder_passes(self):
        name, _ = self.folder()
        out = json.loads(videos.check({"name": name}))
        self.assertTrue(out["passed"], out["problems"])
        self.assertEqual(out["covers"], "00:02:00 of 00:02:00")

    def test_problems(self):
        bad = LEITURA.replace("t=00:50-02:00", "t=01:10-01:30").replace(
            "O autor resume.", "O autor utiliza — vale ressaltar.").replace("-> fim: o fim", "-> nada: o fim")
        name, _ = self.folder(leitura=bad, figures={**FIGURES, "sobra": {}})
        problems = json.loads(videos.check({"name": name}))["problems"]
        for expected in ("gap 00:01:00-00:01:10", "stops at 00:01:30", "unknown link nada",
                         "figure sobra is not in the text", "utilizar", "travessão", "enchimento"):
            with self.subTest(expected):
                self.assertTrue(any(expected in p for p in problems), problems)

    def test_names_cannot_leave_the_work_folder(self):
        self.assertIn("error", json.loads(videos.check({"name": "../../etc"})))

    def test_submit_sends_the_reading_but_not_the_transcript(self):
        name, _ = self.folder()
        out = json.loads(videos.submit({"name": name, "request": "The owner asked to index a video."}))
        self.assertNotIn("error", out, out)
        self.assertEqual(out["branch"], "hermes/video-uma-leitura")
        files = self.origin_files(out["branch"])
        base = f"brain/Videos/{name}/"
        for f in ("video.json", "leitura.markdown", "figuras.json", "figuras/mapa.json"):
            self.assertIn(base + f, files)
        self.assertNotIn(base + "transcript.txt", files)
        body = self.gh_log.read_text()
        self.assertIn("--body-file", body)

    def test_fetch_refuses_other_hosts(self):
        self.assertIn("error", json.loads(videos.fetch({"url": "https://example.com/v"})))
        self.assertIn("error", json.loads(videos.fetch({"url": "http://youtube.com/watch?v=x"})))

    def test_captions_fallbacks(self):
        pick = videos.pick_captions
        self.assertEqual(pick({"language": "pt", "subtitles": {"en": []}}), ("en", True))
        self.assertEqual(pick({"subtitles": {"en": [], "de": []}}), ("en", True))
        self.assertEqual(pick({"language": "pt", "subtitles": {"live_chat": []},
                               "automatic_captions": {"pt": []}}), (None, False))
        self.assertEqual(pick({"automatic_captions": {"pt-orig": []}}), (None, False))

    def test_parse_reports_misplaced_lines(self):
        text = "\n".join([
            "stray", "-> a: b", "### [k=x t=0:00-0:10] Early", "text of x", "-> y: because",
            "# Title", "## Part", "### Loose", "intro", "-> z: q"])
        doc, problems = videos.parse(text)
        self.assertEqual(problems, [
            "link outside a note: -> a: b",
            "note before the first part: ### [k=x t=0:00-0:10] Early",
            "note without [k= t=]: ### Loose",
            "link outside a note: -> z: q"])
        self.assertEqual(doc, {"title": "Title", "parts": [
            {"title": "", "body": "", "notes": [
                {"key": "x", "from": 0, "to": 10, "title": "Early", "body": "text of x",
                 "links": [{"target": "y", "why": "because"}]}]},
            {"title": "Part", "body": "intro", "notes": []}]})

    def test_reading_time(self):
        def doc(body, title=""):
            return {"parts": [{"title": title, "body": body, "notes": []}]}

        self.assertEqual(videos.reading(doc("Uma frase. Outra frase.", title="T")),
                         {"words": 5, "mean": 1.7, "long_share": 0.0, "minutes": 1})
        # 230 words are 0.97 min; a mean sentence over 20 words or over 25 % long words adds 15 %.
        self.assertEqual(videos.reading(doc("palavra " * 230)),
                         {"words": 230, "mean": 230.0, "long_share": 0.0, "minutes": 2})
        sentence = "extraordinario " * 5 + "palavra " * 4 + "fim. "
        self.assertEqual(videos.reading(doc(sentence * 23)),
                         {"words": 230, "mean": 10.0, "long_share": 0.5, "minutes": 2})

    def test_check_dir_needs_its_files(self):
        d = videos.work_dir("2026-11-03-vazio")
        d.mkdir(parents=True)
        self.assertEqual(videos.check_dir(d), {"problems": ["no video.json", "no leitura.markdown",
                                                            "no figuras.json"]})

    def test_check_dir_notes_and_figures_file(self):
        leitura = "# T\n## P\n### [k=a t=0:00-1:00] A\n-> a: \n### [k=a t=1:00-0:50] A again\n"
        _, d = self.folder(leitura=leitura)
        (d / "figuras.json").write_text("{not json")
        problems = videos.check_dir(d)["problems"]
        self.assertEqual(problems[:4], ["a: ends before it starts", "stops at 00:01:00 of 00:02:00",
                                        "repeated note keys", "a: link to a has no reason"])
        self.assertTrue(problems[4].startswith("figuras.json is not JSON: "), problems)
        self.assertEqual(len(problems), 5)

    def test_check_dir_figures(self):
        leitura = LEITURA.replace("![fig](mapa)", "![fig](mapa)\n\n![fig](semjson)\n\n![fig](Bad)\n\n"
                                  "![fig](ausente)")
        full = {f: "x" for f in videos.FIGURE_FIELDS}
        _, d = self.folder(leitura=leitura, figures={"mapa": {"title": "x"}, "semjson": full, "Bad": full})
        self.assertEqual(videos.check_dir(d)["problems"], [
            "figure mapa: no alt", "figure mapa: no takeaway", "figure mapa: no read",
            "figure mapa: no missing", "figure mapa: no evidence",
            "figure semjson: no figuras/semjson.json (Archify's source)",
            "figure Bad: no figuras/Bad.json (Archify's source)",
            "figure ausente has no entry in figuras.json"])

    def fake_ytdlp(self, info):
        """A yt-dlp stub: it writes `info` as the info file and one caption event, and logs its arguments."""
        info_file, log = self.tmp / "info.json", self.tmp / "ytdlp.log"
        info_file.write_text(json.dumps(info))
        script = self.tmp / "bin" / "yt-dlp"
        script.write_text(
            f"#!{sys.executable}\n"
            "import json, sys\n"
            "a = sys.argv[1:]\n"
            f"open({str(log)!r}, 'a').write(' '.join(a) + '\\n')\n"
            "out = a[a.index('-o') + 1]\n"
            "if '--write-info-json' in a:\n"
            f"    open(out.replace('%(ext)s', 'info.json'), 'w').write(open({str(info_file)!r}).read())\n"
            "if '--sub-langs' in a:\n"
            "    sub = a[a.index('--sub-langs') + 1]\n"
            "    events = [{'tStartMs': 1000, 'segs': [{'utf8': 'olá mundo'}]}]\n"
            "    open(out.replace('%(ext)s', sub + '.json3'), 'w').write(json.dumps({'events': events}))\n")
        script.chmod(0o755)
        return log

    def test_fetch_writes_the_work_folder(self):
        base = {"id": "abc", "title": "Uma leitura", "upload_date": "20261103", "duration": 95,
                "webpage_url": "https://www.youtube.com/watch?v=abc", "channel": "Canal", "language": "pt"}
        for info, flag, kind, sub in (
                ({**base, "automatic_captions": {"pt-orig": []}}, "--write-auto-subs", "automatic", "pt-orig"),
                ({**base, "subtitles": {"pt": []}}, "--write-subs", "manual", "pt")):
            with self.subTest(kind):
                log = self.fake_ytdlp(info)
                out = json.loads(videos.fetch({"url": "https://youtu.be/abc"}))
                self.assertNotIn("error", out, out)
                self.assertEqual((out["name"], out["captions"], out["captions_kind"], out["duration"]),
                                 ("2026-11-03-uma-leitura", sub, kind, "00:01:35"))
                self.assertEqual(out["transcript_words"], 3)  # the time stamp counts as a word
                self.assertIn(f"{flag} --sub-langs {sub} --sub-format json3", log.read_text())
                d = videos.work_dir(out["name"])
                self.assertEqual((d / "transcript.txt").read_text(), "[00:00:00] olá mundo\n")
                self.assertTrue((d / "transcript.json3").is_file() and (d / "figuras").is_dir())
                self.assertEqual(json.loads((d / "video.json").read_text())["captions"], sub)

    def test_fetch_refuses_without_captions_bad_answers_and_known_videos(self):
        info = {"id": "abc", "title": "Uma leitura", "upload_date": "20261103", "duration": 95,
                "webpage_url": "https://www.youtube.com/watch?v=abc", "language": "pt"}
        url = {"url": "https://youtu.be/abc"}
        self.fake_ytdlp(info)
        self.assertIn("no captions in the spoken language (pt)", json.loads(videos.fetch(url))["error"])
        self.fake_ytdlp({**{k: v for k, v in info.items() if k != "upload_date"}, "subtitles": {"pt": []}})
        self.assertEqual(json.loads(videos.fetch(url))["error"],
                         "yt-dlp gave an unexpected answer: 'upload_date'")
        self.fake_ytdlp({**info, "subtitles": {"pt": []}})
        (videos.brain().sync(max_age=600) / "brain" / "Videos" / "2026-11-03-uma-leitura").mkdir(parents=True)
        self.assertIn("2026-11-03-uma-leitura is already in the brain", json.loads(videos.fetch(url))["error"])


class Registration(unittest.TestCase):
    """register(ctx) registers what plugin.yaml declares, and a skill file that exists."""

    def test_register(self):
        for alias, name in (("pnotes", "pirsig-notes"), ("pvideos", "pirsig-videos")):
            calls = {"tools": [], "skills": []}

            class Ctx:
                def register_tool(self, name, toolset, schema, handler, **_):
                    assert schema["name"] == name and callable(handler)
                    calls["tools"].append(name)

                def register_skill(self, name, path, **_):
                    assert Path(path).is_file()
                    calls["skills"].append(name)

                def get_config(self, key, default=None):
                    return default

            importlib.import_module(alias).register(Ctx())
            declared = [line.strip()[2:] for line in (HERE / name / "plugin.yaml").read_text().splitlines()
                        if line.startswith("  - ")]
            with self.subTest(name):
                self.assertEqual(sorted(calls["tools"]), sorted(declared))
                self.assertEqual(len(calls["skills"]), 1)


if __name__ == "__main__":
    unittest.main()
