#!/usr/bin/env python3
"""Move the website pins to the head of their source's main.

For each site: rev, the source hash and the numbers the site reads from its commit (commits, the
README's history, npmDepsHash and version), then a build with this flake's nixpkgs, so a pin that
does not build never reaches a pull request.

  python3 scripts/pins.py all                 every site               (just site-pins)
  python3 scripts/pins.py all closed proof    those sites only
  python3 scripts/pins.py all --list          each pin and the head of its main; writes nothing
  python3 scripts/pins.py one ww3 [sha]       one site, to the head of main or to <sha>
                                              (just ww3-pin, just room-pin, the *-pin workflows)
  PIN_BUILD=0 ...                             move the pins and build nothing

`all` prints one line per site: `<site> same <sha>`, `<site> moved <old> <new>` or
`<site> FAILED <step>`; a site that fails is put back as it was, the others go on, and the exit
status is 1 if one failed. `one` prints `old=<sha>` and `new=<sha>` on its last two lines, or
`same=true` when the pin is already there. It needs `nix` with flakes and `git`; it reads the
sources anonymously, so it needs no token. It writes only the pinned files and `result-<site>`
links. The site-pins skill (hermes/skills/site-pins) says how to open the pull request.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

NIX = ["nix", "--extra-experimental-features", "nix-command", "--extra-experimental-features", "flakes"]
SHA = re.compile(r"[0-9a-f]{40}")


@dataclass(frozen=True)
class Site:
    name: str
    repo: str
    file: str
    revname: str = "rev"
    extra: str = ""  # commits | readme | npm
    must: str = "index.html"  # what the build's output must have


SITES = [
    Site("ww3", "h0ffmann/ww3-gpu", "ww3-site/default.nix", extra="commits"),
    Site("closed", "h0ffmann/closed-source", "closed-site/default.nix", extra="commits"),
    Site("hffmnn", "h0ffmann/h0ffmann", "hffmnn-site/default.nix", extra="readme"),
    Site("marola-site", "marola-dev/marola-site", "marola-site/default.nix", must="bin/marola-server"),
    Site("skills", "piabrota/skills", "skills-site/default.nix"),
    Site("proof", "h0ffmann/proof", "proof-site/default.nix", revname="proofRev"),
    Site("pirsig", "piabrota/pirsig", "proof-site/pirsig.nix", revname="pirsigRev"),
    Site("room", "piabrota/room", "room-site/default.nix", extra="npm"),
]
BY_NAME = {s.name: s for s in SITES}


class PinError(Exception):
    """A step that failed; its text names the step."""


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, stdout=subprocess.PIPE, **kw).stdout


def rev_of(text, revname):
    m = re.search(rf'^ *{revname} = "([0-9a-f]{{40}})";', text, re.MULTILINE)
    return m.group(1) if m else None


def head_of(repo):
    out = run("git", "ls-remote", f"https://github.com/{repo}.git", "refs/heads/main")
    return out.split("\t", 1)[0].strip()


def sub_once(pattern, repl, text, what):
    new, n = re.subn(pattern, repl, text, count=1, flags=re.MULTILINE)
    if n != 1:
        raise PinError(f"the rewrite of {what}")
    return new


def rewrite(text, site, old, new, values):
    """The pinned file with rev, the hash after `repo = "<name>";` and the extra values moved."""
    text = sub_once(rf'^( *{site.revname} = "){old}(";)', rf"\g<1>{new}\2", text, site.revname)
    repo = re.escape(f'repo = "{site.repo.split("/", 1)[1]}";')
    text = sub_once(rf'({repo}(?:.*\n)*? *hash = ")sha256-[^"]*(";)', rf"\g<1>{values['hash']}\2", text, "hash")
    if "commits" in values:
        text = sub_once(r"^( *commits = )\d+;", rf"\g<1>{values['commits']};", text, "commits")
    if "readmeCommits" in values:
        text = sub_once(r"^( *readmeCommits = )\d+;", rf"\g<1>{values['readmeCommits']};", text, "readmeCommits")
        text = sub_once(r'^( *readmeFirst = ")[0-9-]*(";)', rf"\g<1>{values['readmeFirst']}\2", text, "readmeFirst")
    if "npmDepsHash" in values:
        text = sub_once(r'^( *npmDepsHash = ")[^"]*(";)', rf"\g<1>{values['npmDepsHash']}\2", text, "npmDepsHash")
        text = sub_once(r'^( *version = ")[^"]*(";)', rf"\g<1>{values['version']}\2", text, "version")
    return text


def prefetch(repo, rev):
    # fetchFromGitHub's hash is the NAR hash of the unpacked tarball, as `flake prefetch` gives it.
    # Where the tarball cannot be had, the same tree over git gives the same hash (a source with
    # export-ignore in .gitattributes would differ; the build then fails on the hash).
    for ref in (f"github:{repo}/{rev}", f"git+https://github.com/{repo}?rev={rev}&shallow=1"):
        try:
            got = json.loads(run(*NIX, "flake", "prefetch", "--json", ref))
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            continue
        if str(got.get("hash", "")).startswith("sha256-"):
            return got
    raise PinError("prefetch")


def values_for(site, new, work):
    src = prefetch(site.repo, new)
    values = {"hash": src["hash"]}
    if site.extra in ("commits", "readme"):
        # A clone with no blobs is enough for a count, and stays small.
        git_dir = Path(work) / f"{site.name}.git"
        try:
            run(
                "git",
                "clone",
                "--quiet",
                "--bare",
                "--filter=blob:none",
                f"https://github.com/{site.repo}.git",
                str(git_dir),
            )
        except subprocess.CalledProcessError as e:
            raise PinError("clone") from e
        if site.extra == "commits":
            values["commits"] = int(run("git", "-C", str(git_dir), "rev-list", "--count", new))
        else:
            # What the profile's generator asks git: `git log --follow --format=%as -- README.md`.
            days = run("git", "-C", str(git_dir), "log", "--follow", "--format=%as", new, "--", "README.md").split()
            if not days:
                raise PinError("the README commits")
            values["readmeCommits"], values["readmeFirst"] = len(days), days[-1]
    elif site.extra == "npm":
        lock = Path(src["storePath"]) / "package-lock.json"
        npm = run(*NIX, "run", "nixpkgs#prefetch-npm-deps", "--", str(lock)).strip().splitlines()
        if not npm or not npm[-1].startswith("sha256-"):
            raise PinError("prefetch-npm-deps")
        day = datetime.fromtimestamp(int(src.get("lastModified") or src["locked"]["lastModified"]), UTC).strftime(
            "%Y-%m-%d"
        )
        values["npmDepsHash"], values["version"] = npm[-1], f"0-unstable-{day}"
    return values


def build(site):
    if os.environ.get("PIN_BUILD", "1") != "1":
        return
    expr = (
        "let f = builtins.getFlake (toString ./.); "
        "pkgs = import f.inputs.nixpkgs { system = builtins.currentSystem; }; "
        f"in pkgs.callPackage ./{site.file} {{ }}"
    )
    out = f"result-{site.name}"
    # The build log goes to stderr, so that stdout keeps only this script's lines.
    done = subprocess.run(
        [*NIX, "build", "--impure", "-o", out, "--print-build-logs", "--expr", expr], stdout=sys.stderr, check=False
    )
    if done.returncode != 0 or not (Path(out) / site.must).exists():
        raise PinError("build")


def move(site, new, work):
    """Move one pin to `new` and build it; on a failure, put the file back and raise PinError."""
    path = Path(site.file)
    orig = path.read_text()
    old = rev_of(orig, site.revname)
    try:
        path.write_text(rewrite(orig, site, old, new, values_for(site, new, work)))
        build(site)
    except PinError:
        path.write_text(orig)
        raise
    except (subprocess.CalledProcessError, ValueError, KeyError) as e:
        path.write_text(orig)
        raise PinError(f"{type(e).__name__} {e}") from e


def one(args):
    if not args or args[0] not in BY_NAME:
        sys.exit(f"usage: pins.py one <{'|'.join(BY_NAME)}> [sha]")
    site = BY_NAME[args[0]]
    old = rev_of(Path(site.file).read_text(), site.revname)
    if not old:
        sys.exit(f"no {site.revname} in {site.file}")
    new = args[1] if len(args) > 1 else head_of(site.repo)
    if not SHA.fullmatch(new):
        sys.exit(f"not a whole commit (40 hex characters): {new}")
    if new == old:
        print(f"{site.name} is pinned at {old} already.")
        print("same=true")
        return 0
    with tempfile.TemporaryDirectory() as work:
        try:
            move(site, new, work)
        except PinError as e:
            sys.exit(f"{site.name}: {e} failed; {site.file} is as it was")
    print(f"old={old}")
    print(f"new={new}")
    return 0


def all_sites(args):
    listing = bool(args) and args[0] == "--list"
    wanted = args[1:] if listing else args
    unknown = [w for w in wanted if w not in BY_NAME]
    if unknown:
        sys.exit(f"no such site: {' '.join(unknown)} (the sites: {' '.join(BY_NAME)})")
    status = 0
    with tempfile.TemporaryDirectory() as work:
        for site in SITES:
            if wanted and site.name not in wanted:
                continue
            old = rev_of(Path(site.file).read_text(), site.revname)
            if not old:
                print(f"{site.name} FAILED no {site.revname} in {site.file}", flush=True)
                status = 1
                continue
            try:
                new = head_of(site.repo)
            except subprocess.CalledProcessError:
                new = ""
            if not SHA.fullmatch(new):
                print(f"{site.name} FAILED the head of {site.repo}'s main", flush=True)
                status = 1
            elif new == old:
                print(f"{site.name} same {old}", flush=True)
            elif listing:
                print(f"{site.name} behind {old} {new}", flush=True)
            else:
                try:
                    move(site, new, work)
                    print(f"{site.name} moved {old} {new}", flush=True)
                except PinError as e:
                    print(f"{site.name} FAILED {e}", flush=True)
                    status = 1
    return status


def main(argv):
    os.chdir(Path(__file__).resolve().parent.parent)
    if argv[:1] in (["-h"], ["--help"]) or not argv or argv[0] not in ("one", "all"):
        print(__doc__.strip())
        return 0 if argv[:1] in (["-h"], ["--help"]) else 2
    return one(argv[1:]) if argv[0] == "one" else all_sites(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
