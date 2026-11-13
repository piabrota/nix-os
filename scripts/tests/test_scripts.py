"""Offline tests of the Python scripts of scripts/: a stub `gh`, local git repositories, the real
pinned files with made-up values. No network, no token.

  python3 -m unittest discover -s scripts/tests      (or: just scripts-test)
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent.parent
ROOT = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))

import cert_check
import context_size
import pins

GH_STUB = r"""#!/usr/bin/env python3
import os, sys
with open(os.environ["LOG"], "a") as log:
    log.write("gh " + " ".join(sys.argv[1:]) + "\n")
answers = {
    "repos/piabrota/mixed/": ["h0ffmann", "piabrota-hermes[bot]", "claude", "dependabot[bot]", "aracyla", "-",
                              "claudette", "x[bot]y"],
    "repos/piabrota/robots/": ["piabrota-ops[bot]", "ouroboric-pr-bot[bot]", "claude"],
    "repos/piabrota/people/": ["h0ffmann", "h0ffmann", "robkler"],
    "repos/piabrota/empty/": [],
    "repos/other/mixed/": ["h0ffmann"],
}
for prefix, logins in answers.items():
    if sys.argv[3].startswith(prefix):
        print("\n".join(logins))
        sys.exit(0)
print("gh: HTTP 404", file=sys.stderr)
sys.exit(1)
"""


def run(*cmd, env=None, cwd=None):
    return subprocess.run(cmd, text=True, capture_output=True, env=env, cwd=cwd, check=False)


class CommitCounts(unittest.TestCase):
    def setUp(self):
        self.work = Path(tempfile.mkdtemp())
        (self.work / "gh").write_text(GH_STUB)
        (self.work / "gh").chmod(0o755)
        self.log = self.work / "calls.log"
        self.env = {**os.environ, "PATH": f"{self.work}:{os.environ['PATH']}", "LOG": str(self.log)}
        self.env.pop("COMMIT_COUNTS_OWNER", None)

    def counts(self, *names, **env):
        return run(sys.executable, str(SCRIPTS / "commit_counts.py"), *names, env={**self.env, **env})

    def test_the_rule(self):
        # [bot] and exactly "claude" are agents; a person, a missing account, "claudette" and a
        # login that only contains [bot] are human.
        self.assertEqual(self.counts("mixed").stdout, "mixed: commits = { human = 5; agent = 3; };\n")
        self.assertEqual(self.counts("robots").stdout, "robots: commits = { human = 0; agent = 3; };\n")
        self.assertEqual(self.counts("people").stdout, "people: commits = { human = 3; agent = 0; };\n")
        self.assertEqual(self.counts("empty").stdout, "empty: commits = { human = 0; agent = 0; };\n")

    def test_no_data_then_goes_on(self):
        out = self.counts("missing", "people")
        self.assertEqual(out.stdout, "missing: no data\npeople: commits = { human = 3; agent = 0; };\n")
        self.assertEqual(out.returncode, 1)
        self.assertEqual(self.counts("people").returncode, 0)

    def test_another_owner(self):
        out = self.counts("mixed", COMMIT_COUNTS_OWNER="other")
        self.assertEqual(out.stdout, "mixed: commits = { human = 1; agent = 0; };\n")

    def test_the_request(self):
        self.counts("people")
        self.assertEqual(
            self.log.read_text(),
            'gh api --paginate repos/piabrota/people/commits?per_page=100 --jq .[] | (.author.login // "-")\n',
        )

    def test_help_calls_nothing(self):
        out = self.counts("--help")
        self.assertIn("agent when its GitHub author login ends with [bot]", out.stdout)
        self.assertFalse(self.log.exists())

    @unittest.skipUnless(run("sh", "-c", "command -v nix-instantiate").returncode == 0, "no nix-instantiate")
    def test_names_from_data_nix(self):
        self.counts()
        asked = [line.split("/")[2] for line in self.log.read_text().splitlines()]
        want = ["mu", "dojo", ".github", "pirsig", "gramatico", "skills", "alerts", "rax", "agents", "nix-os", "ihero"]
        self.assertEqual(asked, want)


class ContextSize(unittest.TestCase):
    def test_levels(self):
        self.assertEqual(context_size.level(30000)[0], "ok")
        self.assertEqual(context_size.level(30001), ("WARN", "30001 / 32000 (margin 2000)"))
        self.assertEqual(context_size.level(32001), ("FAIL", "32001 / 32000: Hermes drops the middle"))

    def test_counts_characters_not_bytes(self):
        root = Path(tempfile.mkdtemp())
        (root / "AGENTS.md").write_text("é" * 31000, encoding="utf-8")  # 62000 bytes
        with mock.patch("sys.stdout"):
            self.assertEqual(context_size.main(root), 0)


class CertCheck(unittest.TestCase):
    def test_entries(self):
        work = Path(tempfile.mkdtemp())
        (work / "d.txt").write_text("# a comment\n\na.piabrota.art  piabrota2\nb.piabrota.art off\n")
        self.assertEqual(
            cert_check.entries(work / "d.txt"), [("a.piabrota.art", "piabrota2"), ("b.piabrota.art", "off")]
        )

    def test_coverage(self):
        root = Path(tempfile.mkdtemp())
        run("git", "init", "-q", cwd=root)
        (root / "a.nix").write_text('{ x = "new.piabrota.art"; y = "https://piabrota.art/"; }\n')
        (root / "b.txt").write_text("other.piabrota.art\n")
        run("git", "add", ".", cwd=root)
        with mock.patch("sys.stdout"), mock.patch("sys.stderr") as err:
            self.assertEqual(cert_check.coverage({"piabrota.art"}, root), 1)
        self.assertIn(
            "not in scripts/domains.txt: new.piabrota.art", "".join(c.args[0] for c in err.write.call_args_list)
        )
        with mock.patch("sys.stdout"):
            self.assertEqual(cert_check.coverage({"piabrota.art", "new.piabrota.art"}, root), 0)

    def test_every_name_of_this_repository_is_listed(self):
        names = {n for n, _ in cert_check.entries(SCRIPTS / "domains.txt")}
        with mock.patch("sys.stdout"):
            self.assertEqual(cert_check.coverage(names, ROOT), 0)


class Pins(unittest.TestCase):
    OLD_NEW = "0" * 40

    def test_every_pinned_file_rewrites(self):
        for site in pins.SITES:
            with self.subTest(site=site.name):
                text = (ROOT / site.file).read_text()
                old = pins.rev_of(text, site.revname)
                self.assertRegex(old or "", pins.SHA)
                values = {"hash": "sha256-NEW="}
                if site.extra == "commits":
                    values["commits"] = 4242
                if site.extra == "readme":
                    values.update(readmeCommits=77, readmeFirst="2001-02-03")
                if site.extra == "npm":
                    values.update(npmDepsHash="sha256-NPM=", version="0-unstable-2001-02-03")
                out = pins.rewrite(text, site, old, self.OLD_NEW, values)
                self.assertEqual(pins.rev_of(out, site.revname), self.OLD_NEW)
                self.assertIn('"sha256-NEW="', out)
                for v in values.values():
                    self.assertIn(str(v), out)
                # Only the pinned lines change; another source of the same file keeps its hash.
                changed = [a for a, b in zip(text.splitlines(), out.splitlines(), strict=True) if a != b]
                self.assertEqual(len(changed), len(values) + 1)

    def test_a_failed_step_puts_the_file_back(self):
        site = pins.BY_NAME["skills"]
        before = (ROOT / site.file).read_text()
        cwd = os.getcwd()
        os.chdir(ROOT)
        try:
            with (
                mock.patch.object(pins, "values_for", side_effect=pins.PinError("prefetch")),
                self.assertRaises(pins.PinError),
            ):
                pins.move(site, self.OLD_NEW, "/nonexistent")
            with (
                mock.patch.object(pins, "values_for", return_value={"hash": "sha256-X="}),
                mock.patch.object(pins, "build", side_effect=pins.PinError("build")),
                self.assertRaises(pins.PinError),
            ):
                pins.move(site, self.OLD_NEW, "/nonexistent")
        finally:
            os.chdir(cwd)
        self.assertEqual((ROOT / site.file).read_text(), before)

    def test_one_refuses_a_short_sha_and_knows_the_same_pin(self):
        out = run(sys.executable, str(SCRIPTS / "pins.py"), "one", "room", "abc123")
        self.assertEqual(out.returncode, 1)
        self.assertIn("not a whole commit", out.stderr)
        rev = pins.rev_of((ROOT / "room-site/default.nix").read_text(), "rev")
        out = run(sys.executable, str(SCRIPTS / "pins.py"), "one", "room", rev)
        self.assertEqual(out.stdout.splitlines()[-1], "same=true")

    def test_unknown_site(self):
        out = run(sys.executable, str(SCRIPTS / "pins.py"), "all", "nope")
        self.assertEqual(out.returncode, 1)
        self.assertIn("no such site: nope", out.stderr)


class PrStack(unittest.TestCase):
    """An origin with main and three PR heads: 1 and 2 touch other files, 3 conflicts with 1."""

    def setUp(self):
        self.work = Path(tempfile.mkdtemp())
        origin, seed = self.work / "origin.git", self.work / "seed"
        env = {
            **os.environ,
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t",
        }
        self.env = env

        def git(*a, cwd=seed):
            done = run("git", *a, env=env, cwd=cwd)
            self.assertEqual(done.returncode, 0, done.stderr)
            return done.stdout.strip()

        git("init", "-q", "--bare", "-b", "main", str(origin), cwd=self.work)
        git("init", "-q", "-b", "main", str(seed), cwd=self.work)
        (seed / "a").write_text("a\n")
        git("add", "a")
        git("commit", "-qm", "base")
        git("remote", "add", "origin", str(origin))
        git("push", "-q", "origin", "main")
        for pr, name, text in ((1, "x", "one\n"), (2, "y", "two\n"), (3, "x", "three\n")):
            git("switch", "-qc", f"pr{pr}", "main")
            (seed / name).write_text(text)
            git("add", name)
            git("commit", "-qm", f"pr {pr}")
            git("push", "-q", "origin", f"pr{pr}:refs/pull/{pr}/head")
        git("switch", "-qc", "stack", "main")
        git("merge", "-q", "--no-ff", "pr1", "-m", "m1")
        git("merge", "-q", "--no-ff", "pr2", "-m", "m2")
        git("push", "-q", "origin", "stack")
        self.clone = self.work / "clone"
        git("clone", "-q", str(origin), str(self.clone), cwd=self.work)

    def stack(self, *args):
        return run(sys.executable, str(SCRIPTS / "pr_stack.py"), *args, env=self.env, cwd=self.clone)

    def test_plan(self):
        out = self.stack("plan", "1", "2")
        self.assertEqual(
            out.stdout, "#1  clean\n#2  clean\nplan: all 2 PRs stack cleanly on origin/main, in this order\n"
        )
        out = self.stack("plan", "1", "3", "2")
        self.assertEqual(out.returncode, 1)
        self.assertEqual(out.stdout, "#1  clean\n#3  CONFLICT in:\n      x\n#2  clean\n")

    def test_check(self):
        out = self.stack("check", "stack", "1", "2")
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("check: merge stack with a merge commit", out.stdout)
        out = self.stack("check", "stack", "1", "3")
        self.assertEqual(out.returncode, 1)
        self.assertIn("FAIL  #3 head", out.stdout)

    def test_no_such_pr(self):
        out = self.stack("plan", "9")
        self.assertEqual(out.returncode, 2)
        self.assertIn("no PR #9 on origin", out.stderr)


if __name__ == "__main__":
    unittest.main()
