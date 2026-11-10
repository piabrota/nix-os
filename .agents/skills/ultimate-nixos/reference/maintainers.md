# Nixpkgs maintainers and committer workflow

Reference for people who already hold maintainer or committer status in nixpkgs. For onboarding steps (adding yourself to the maintainer list, becoming a committer), see [CONTRIBUTING.md](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md).

## Authoritative in-tree docs

Read these before guessing:

| Topic | Location |
| :--- | :--- |
| Maintainer role and merge bot | [maintainers/README.md](https://github.com/NixOS/nixpkgs/blob/master/maintainers/README.md) |
| Package layout and conventions | [pkgs/README.md](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md) |
| CI layout, merge bot rules, `nixpkgs-vet` | [ci/README.md](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md) |
| PR checklist | [.github/PULL_REQUEST_TEMPLATE.md](https://github.com/NixOS/nixpkgs/blob/master/.github/PULL_REQUEST_TEMPLATE.md) |
| Critical packages (extra care) | [ci/OWNERS](https://github.com/NixOS/nixpkgs/blob/master/ci/OWNERS) |
| General contribution flow | [CONTRIBUTING.md](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md) |

## Teams

Teams are defined in `maintainers/team-list.nix`:

- `members`: list of maintainers
- `scope`: what the team maintains
- `shortName`: human-readable name
- `enableFeatureFreezePing`: critical teams pinged during feature freezes (optional)
- `github`: linked GitHub team for review requests (optional)

To find `githubMaintainers` for a team with a `github` field:

```bash
nix eval -f lib teams.someTeam.githubMaintainers --json | jq
```

## Branches

- **`master`**: default target for most changes.
- **`staging`**: for changes causing ~500+ rebuilds. Changes with ~1000+ rebuilds must go here. Kernel changes and "rebuild all NixOS tests" follow special rules in CONTRIBUTING.
- **`staging-next`**: staging changes flow here before merging into `master`.
- **`release-YY.MM`**: target for backports (e.g. `release-25.11`). Never target channel branches (`nixos-25.11`, `nixpkgs-25.11-darwin`).

## Commit messages

- One logical change per commit. Squash whitespace-only or fixup follow-ups.
- No period at end of the subject line.
- Prefix with the package attribute: `vim: 1.0.0 -> 2.0.0` (triggers OfBorg automatic builds for that attr).
- Area-specific conventions: `doc/README.md`, `lib/README.md`, `nixos/README.md`, `pkgs/README.md`.

## OfBorg (CI builder)

- Trigger lines must start with `@ofborg` (case insensitive). GitHub may not autocomplete it; verify it links to the ofborg user.
- `@ofborg build attr1 attr2` -- builds each listed attr.
- `@ofborg test test1 test2` -- runs `nixosTests.test1`, etc.
- `@ofborg eval` -- rarely needed; eval runs automatically on PR open/update.
- The parser is line-based: only words after the command on that line are treated as attrs.
- `WIP:` or `[WIP]` in the PR title suppresses automatic OfBorg builds. Draft PRs do not suppress them.
- Do not fire expensive builds (browsers, toolchains, mass rebuilds) without reviewing the diff first.

## nixpkgs-review

Build dependents locally to catch breakage before or alongside OfBorg:

```bash
nix-shell -p nixpkgs-review --run "nixpkgs-review pr <PR_NUMBER>"
# or
nix run nixpkgs#nixpkgs-review -- pr <PR_NUMBER>
```

Other modes:
- `nixpkgs-review wip` -- uncommitted changes
- `nixpkgs-review rev HEAD` -- last commit

Upstream: [Mic92/nixpkgs-review](https://github.com/Mic92/nixpkgs-review).

## nixpkgs-vet (CI validation)

[nixpkgs-vet](https://github.com/NixOS/nixpkgs-vet) (v0.2.0, March 2026) validates `pkgs/by-name` structure per RFC 140. It checks:

- Directory layout `pkgs/by-name/${shard}/${name}/package.nix`
- Naming rules (ASCII `a-z`, `A-Z`, `0-9`, `-`, `_`; no leading digit or `-`)
- Name uniqueness when lowercased
- `callPackage` usage

Run locally:

```bash
ci/nixpkgs-vet.sh <BASE_BRANCH>
```

## GitHub Actions and CI

- "PR / ..." required checks are separate from OfBorg.
- OfBorg is not always a required check (noted in CONTRIBUTING merge bot section).
- nixpkgs-merge-bot is integrated into nixpkgs' GitHub Actions (moved in-repo).

## nixpkgs-merge-bot

Trigger with a comment:

```text
@NixOS/nixpkgs-merge-bot merge
```

**Constraints** (from ci/README.md):

- Target branch is an allowed development branch.
- Diff only touches `pkgs/by-name/*` package files.
- PR author is a committer, a backport label path, [@r-ryantm](https://github.com/r-ryantm), or committer-approved.
- Commenter is in [@NixOS/nixpkgs-maintainers](https://github.com/orgs/NixOS/teams/nixpkgs-maintainers) and maintains all touched packages.
- PR is not a draft.
- Bot waits for OfBorg checks except Darwin.

Policy evolves; always read [ci/README.md](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md).

## r-ryantm and nixpkgs-update

- [@r-ryantm](https://github.com/r-ryantm) opens version-bump PRs via [nixpkgs-update](https://nix-community.github.io/nixpkgs-update/).
- Review bot-opened PRs like any bump: check the changelog, verify the hash update, confirm tests pass.
- Merge bot is the standard path for clean bot PRs on `pkgs/by-name` packages.

## Review and merge norms

- Non-blocking feedback is the default. Use GitHub "Request changes" explicitly for blocking feedback.
- Give maintainers roughly one week before merging changes they have not endorsed. Exceptions: security fixes, packages in `ci/OWNERS`.
- Prefer conventional comments (`suggestion:`, `nitpick:`, `question:`) to signal intent.
- Committers may push small fixes directly to contributor branches when allowed; `gh pr checkout` branches need care with force-push (see CONTRIBUTING).

## NixOS tests

- Declared in `nixos/tests/`. Run locally per the NixOS manual.
- OfBorg: `@ofborg test driverTestName`.
- Linux-only (full VM tests require QEMU).

## Quick reference

| Task | Command or action |
| :--- | :--- |
| Local CI-style validation | `ci/nixpkgs-vet.sh <base>` |
| Build PR packages locally | `nixpkgs-review pr <NUM>` |
| Test uncommitted changes | `nixpkgs-review wip` |
| Trigger OfBorg build | `@ofborg build attr1 attr2` |
| Trigger OfBorg NixOS test | `@ofborg test testName` |
| Merge via bot | `@NixOS/nixpkgs-merge-bot merge` |
| Backport | Label on master PR or cherry-pick to `release-YY.MM` |

## Key references

- [maintainers/README.md](https://github.com/NixOS/nixpkgs/blob/master/maintainers/README.md)
- [ci/README.md](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md)
- [OfBorg README](https://github.com/NixOS/ofborg/blob/master/README.md)
- [nixpkgs-review](https://github.com/Mic92/nixpkgs-review)
- [nixpkgs-vet](https://github.com/NixOS/nixpkgs-vet)
- [nixpkgs-update / r-ryantm](https://nix-community.github.io/nixpkgs-update/r-ryantm/)
- [nixpkgs-merge-bot RFC 172](https://github.com/NixOS/rfcs/pull/172)
