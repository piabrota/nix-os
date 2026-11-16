# Rules for marola-front and marola-back

These rules add to the rules of every seat. They apply to the two marola repositories only. A human
or Hermes (the operator) can change them only through a pull request to piabrota/nix-os.

## When it applies

- Use this file only when the task names `marola-dev/marola-front` or `marola-dev/marola-back`.
- The plan is MIP-0092 in `marola-dev/marola`. Its status is Draft. When the repository's `AGENTS.md`
  or an accepted MIP says something else, that text wins.

## Get the code

- Run `marola-clone marola-front` or `marola-clone marola-back` in your working folder.
- If the command does not exist, or the clone fails for lack of a token, stop and tell the operator.
- Read the `AGENTS.md` of the clone first. It wins when it is stricter than this file.
- Two rules of this box win over it: you never push, and your branch is `hermes/<issue>-<slug>`.
  Hermes can push only `hermes/*` branches.

## Keep front and back apart

MIP-0092, section 5.4, as proposed:

- The two repositories share one artifact: the OpenAPI contract `openapi.yaml`.
- The back owns the contract. The front pins a released tag of it in `openapi.version`.
- Share no code, no CI and no build.
- Every path starts with `/api/v1`. A change inside a version only adds. The front ignores a field
  that it does not know.
- Share no database and no secret.
- A task for one repository never edits the other one.

## marola-front

Apply this part when the repository has these files:

- The stack is Vite and TypeScript. The map is MapLibre. Do not use Mapbox.
- The pages are under `/pt-br/` and `/en/`. Change both language catalogs together.
- Only the code in `src/api/` calls the back.
- `marola-site` is the reference for parity. Read it. Never edit it.

## marola-back

- The stack is Rust and Loco. In v1 `/api/v1` is read-only.
- The database question is open. Use no feature that only Postgres has.

## What this box cannot check

Playwright with a browser, `oasdiff`, the Cloudflare deploy and the live API do not run here. Do not
install them. Write each one in your report with the words "runs in CI" and the sign ⚠.

## Who builds what

- The seat `front-builder` works on `marola-front` only. The seat `builder` works on `marola-back`.
  The two work at the same time, each in its own clone. They share one reviewer.
- The reviewer reviews one diff at a time. A second request waits until the first verdict.

## Memory

- The three seats and the daemon share 4 GiB (3 GiB before the kernel slows them). Each builder
  runs one build at a time.
- For Rust, run `CARGO_BUILD_JOBS=1 nice -n 10 <command>`. For Node, run `nice -n 10 <command>`.

## Files you never touch

- `.github/workflows/`. No App of this box can change workflows.

## Handoff

1. Commit on `hermes/<issue>-<slug>`. Put a `Tested:` line in the message. Name only commands that you
   ran here.
2. Make the bundle: `git -C <clone> bundle create /var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.bundle origin/main..HEAD`
3. Check it: `git -C <clone> bundle verify /var/lib/rig-outbox/marola/<repo>-<issue>-<slug>.bundle`
4. Write `<repo>-<issue>-<slug>.md` next to the bundle. Put in it: the branch, the files, the `Tested:`
   lines, what you did not run, and the verdict of the reviewer seat.

The operator fetches the bundle, reads it, pushes the branch and opens the pull request as
`marola-pr-bot`. You hold a read-only token only.

## Two runtimes

The same task can run on omp (rig `piabrota-dev`) or on Claude Code (rig `piabrota-dev-claude`).
The rules do not change. In the Claude Code rig, the reviewer reads a builder's clone at
`/var/lib/openrig/work/piabrota-dev-claude/<builder or front-builder>/<repo>`. In the omp rig, the
clones are at `/var/lib/openrig/work/<repo>`. The bundle name ends with `-omp` or
`-claude`. The operator says which one in the task.

## Never

- Never use, ask for or look for a token or a key.
- Never mention `marola-merge-bot`.
- Never add a dependency without saying so in the report.
- Never copy code from one of the two repositories to the other.
