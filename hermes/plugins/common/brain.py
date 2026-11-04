"""The pirsig brain as a git checkout, and pull requests to it.

Copied into each plugin's directory at build time (hermes.nix), so each plugin stays one
self-contained directory. Standard library only.

Git runs as the hermes user: hermes-github.nix gives git a credential helper and gh a token
of the piabrota-hermes App. The plugins push only `hermes/*` branches and only open pull
requests; that rule is checked here, because the deny list of custom-dangerous-patterns sees
the terminal tool only, not a plugin's own subprocesses.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import time
import unicodedata
from pathlib import Path

BRANCH_PREFIX = "hermes/"
DEFAULT_REPO = "piabrota/pirsig"
DEFAULT_BASE = "main"
# A fresh clone is enough for a search for this long; a submission always fetches.
REFRESH_SECONDS = 600
# What the checkout holds: the brain and the video policy. The rest (Rust, the apps) stays out.
SPARSE = ["brain", ".claude/agents"]
GIT_TIMEOUT = 180


class BrainError(Exception):
    """A failure to report to the model as the tool's error."""


def data_dir(plugin: str) -> Path:
    try:
        from plugins.plugin_storage import plugin_data_dir  # Hermes, at run time

        return Path(plugin_data_dir(plugin))
    except ImportError:
        home = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
        path = home / "plugin-data" / plugin
        path.mkdir(parents=True, exist_ok=True)
        return path


def slugify(text: str, words: int = 6) -> str:
    plain = unicodedata.normalize("NFD", text.lower())
    plain = "".join(c for c in plain if not unicodedata.combining(c))
    parts = re.sub(r"[^a-z0-9]+", " ", plain).split()
    return "-".join(parts[:words]) or "untitled"


def run(args: list[str], cwd: Path | None = None, timeout: int = GIT_TIMEOUT) -> str:
    try:
        done = subprocess.run(
            args, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False
        )
    except FileNotFoundError as e:
        raise BrainError(f"{args[0]} is not on PATH") from e
    except subprocess.TimeoutExpired as e:
        raise BrainError(f"{' '.join(args[:2])} took more than {timeout} s") from e
    if done.returncode != 0:
        tail = (done.stderr or done.stdout).strip().splitlines()[-3:]
        raise BrainError(f"{' '.join(args[:3])} failed: {' / '.join(tail)}")
    return done.stdout


class Brain:
    """A shallow, sparse checkout of the brain repository in the plugin's data directory."""

    def __init__(self, root: Path, repo: str = DEFAULT_REPO, base: str = DEFAULT_BASE):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
            raise BrainError(f"not a GitHub repository: {repo}")
        self.repo = repo
        self.base = base
        self.path = root / repo.replace("/", "__")

    @property
    def url(self) -> str:
        return f"https://github.com/{self.repo}"

    def git(self, *args: str) -> str:
        return run(["git", *args], cwd=self.path)

    def sync(self, max_age: int = 0) -> Path:
        """Check out the tip of the base branch; skip the fetch if the last one is recent."""
        stamp = self.path / ".git" / "pirsig-plugin-fetched"
        if not (self.path / ".git").is_dir():
            self.path.parent.mkdir(parents=True, exist_ok=True)
            run(["git", "clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse",
                 "--branch", self.base, self.url, str(self.path)])
            self.git("sparse-checkout", "set", *SPARSE)
        elif max_age and stamp.exists() and time.time() - stamp.stat().st_mtime < max_age:
            return self.path
        else:
            self.git("fetch", "--quiet", "--depth", "1", "origin", self.base)
            self.git("checkout", "--quiet", "--force", "-B", self.base, "FETCH_HEAD")
            self.git("clean", "--quiet", "-fd")
        stamp.touch()
        return self.path

    def branch_name(self, slug: str) -> str:
        """`hermes/<slug>`, with `-2`, `-3`... when the branch is already on GitHub."""
        heads = self.git("ls-remote", "--heads", "origin", f"{BRANCH_PREFIX}{slug}*")
        taken = {line.split("refs/heads/", 1)[1] for line in heads.splitlines() if "refs/heads/" in line}
        name, n = f"{BRANCH_PREFIX}{slug}", 2
        while name in taken:
            name, n = f"{BRANCH_PREFIX}{slug}-{n}", n + 1
        return name

    def open_pr(self, files: dict[str, str | bytes], slug: str, title: str, body: str) -> dict:
        """Commit `files` (paths relative to the repository) on a new hermes/* branch, push it
        and open a pull request against the base branch. Returns the branch and the PR URL."""
        if not files:
            raise BrainError("nothing to submit")
        self.sync()
        branch = self.branch_name(slug)
        # The ruleset on GitHub also blocks other branches; this refuses before any git write.
        if not branch.startswith(BRANCH_PREFIX):
            raise BrainError(f"refused: {branch} is not a {BRANCH_PREFIX}* branch")
        targets = self.checked_targets(files)
        self.push_branch(branch, targets, title, body)
        url = self.create_pr(branch, title, body)
        return {"branch": branch, "pr": url.splitlines()[-1] if url else ""}

    def checked_targets(self, files: dict[str, str | bytes]) -> list[tuple[str, Path, str | bytes]]:
        """Resolve every path before any write, so one bad path leaves the checkout untouched."""
        allowed = (self.path / "brain").resolve()
        targets = []
        for rel, content in files.items():
            target = (self.path / rel).resolve()
            if allowed not in target.parents:
                raise BrainError(f"refused: {rel} is outside brain/")
            if target.exists():
                raise BrainError(f"refused: {rel} is already in {self.repo}; a note is never rewritten")
            targets.append((rel, target, content))
        return targets

    def push_branch(self, branch: str, targets: list[tuple[str, Path, str | bytes]],
                    title: str, body: str) -> None:
        self.git("checkout", "--quiet", "-B", branch)
        try:
            for _, target, content in targets:
                target.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(content, bytes):
                    target.write_bytes(content)
                else:
                    target.write_text(content, encoding="utf-8")
            self.git("add", "--sparse", "--", *(rel for rel, _, _ in targets))
            self.git("commit", "--quiet", "-m", title, "-m", commit_body(body))
            self.git("push", "--quiet", "origin", f"HEAD:refs/heads/{branch}")
        finally:
            # Back to the base even when git failed, so the next call starts from a clean tree.
            self.git("checkout", "--quiet", "--force", self.base)
            self.git("clean", "--quiet", "-fd")

    def create_pr(self, branch: str, title: str, body: str) -> str:
        """Open the PR with `gh` and return its URL."""
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
            f.write(body)
            body_file = f.name
        try:
            return run(["gh", "pr", "create", "--repo", self.repo, "--base", self.base,
                        "--head", branch, "--title", title, "--body-file", body_file]).strip()
        finally:
            os.unlink(body_file)

    def notes(self) -> list[dict]:
        """Every Markdown note of the brain's slip-box and inbox: stem, title, zid, kind."""
        out = []
        for folder in ("Zettelkasten", "Inbox"):
            for path in sorted((self.path / "brain" / folder).glob("*.md")):
                fm, body = front_matter(path.read_text(encoding="utf-8", errors="replace"))
                out.append({
                    "stem": path.stem,
                    "title": fm.get("title") or path.stem,
                    "zid": fm.get("zid", ""),
                    "kind": fm.get("kind") or fm.get("type") or "",
                    "folder": folder,
                    "body": body,
                })
        return out


def open_brain(plugin: str, ctx=None) -> Brain:
    """The Brain of `plugin`. Hermes' plugin config sets `repo` and `base`; without a ctx (the
    tests) the defaults hold."""
    get = (lambda k, d: ctx.get_config(k, default=d)) if ctx is not None else (lambda k, d: d)
    return Brain(data_dir(plugin), repo=get("repo", DEFAULT_REPO), base=get("base", DEFAULT_BASE))


def commit_body(pr_body: str) -> str:
    """The first paragraph of the PR body, the commit's reason."""
    for block in pr_body.split("\n\n"):
        text = block.strip()
        if text and not text.startswith("#"):
            return text
    return pr_body.strip()


def front_matter(text: str) -> tuple[dict, str]:
    """The flat `key: value` lines of `---` front matter, as strings (no YAML library here)."""
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 4)
    if end < 0:
        return {}, text
    fm = {}
    for line in text[4:end].splitlines():
        key, sep, value = line.partition(":")
        if sep and key and not key.startswith((" ", "-")):
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] == '"':
                try:
                    value = json.loads(value)
                except ValueError:
                    value = value[1:-1]
            fm[key.strip()] = value
    return fm, text[end + 4:].lstrip("\n")


def yaml_str(value: str) -> str:
    """A YAML scalar that is also JSON: safe for any title."""
    return json.dumps(value, ensure_ascii=False)


def ok(**fields) -> str:
    return json.dumps(fields, ensure_ascii=False)


def fail(message: str, **fields) -> str:
    return json.dumps({"error": message, **fields}, ensure_ascii=False)
