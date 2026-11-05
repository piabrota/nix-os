# Rules of every wave-forecaster-dev seat

These rules add to the rules of every piabrota seat. They apply to work on h0ffmann/chaceon, the
Rust port of WAVEWATCH III (WW3). A human or Hermes can change them only through a pull request to
piabrota/nix-os.

## The repository binds you

- Get the code with `chaceon-clone chaceon` in your working folder. The command clones
  h0ffmann/chaceon with a read-only token and fetches `WW3/` at the pin. Use `git -C chaceon fetch`
  later: the clone keeps the same token helper.
- Read `chaceon/AGENTS.md` before you change anything. It binds you, with one difference: the
  gates below that this box cannot run. Read `chaceon/.claude/skills/ww3-port/SKILL.md` too:
  omp does not find skills by itself.
- `chaceon/WW3/` is the Fortran reference at commit `92e2cf66`. Read it. Never edit it.

## What this box can check, and what it cannot

This box has no Docker, no GPU, no Vulkan and no Fortran compiler. So:

- You can run `just check`, `just lint-sh` and `cargo` in `chaceon/rust`.
- You cannot run the Fortran reference, the gdb captures, the `just <x>-cmp` replays (they run in
  Docker), `just spirv`, `just spirv-replay` or `just ptx`. Do not try to install them. The owner
  runs these gates on the owner's machine. `chaceon/AGENTS.md` says that a missing tool is a reason to
  install it: on this box, it is a reason to stop and say so.
- So a routine that leaves this box has the status `translated`, never `routine`, `host`, `cuda`
  or `spirv`. Write every gate that you did not run in the port report, with `⚠` and the words
  "runs on the owner's machine".

## Memory and disk

- The daemon and every seat share one memory budget. Run one build at a time, and start it with
  `CARGO_BUILD_JOBS=1 nice -n 10`, for example `CARGO_BUILD_JOBS=1 nice -n 10 just check`.
- Install the Rust toolchain once per seat: `rustup toolchain install 1.99.1 --profile minimal`,
  then `rustup default 1.99.1`. Do not install the nightly toolchains of `rust/gpu-cuda` or
  `rust/gpu-spirv`.

## Branches and handoff

- Work on the branch `hermes/wf-<slug>`: a few lowercase words for the routine or the package.
- Commit on that branch. Write the message as `chaceon/AGENTS.md` says, with a `Tested:` trailer
  that names only the commands that you ran on this box. Add no `Co-Authored-By` line.
- To hand your work to the operator, write a bundle in the outbox, then say its path:

  ```console
  git -C chaceon bundle create /var/lib/rig-outbox/wave-forecaster-dev/<branch-slug>.bundle origin/main..HEAD
  git -C chaceon bundle verify /var/lib/rig-outbox/wave-forecaster-dev/<branch-slug>.bundle
  ```

  The operator fetches the bundle, reads it and pushes it. You never push.

## Never

- Never run anything on a GPU.
- Never add a Rust test (`#[test]`, `tests/`, `benches/`, `dev-dependencies`).
- Never change a comparison tool's tolerance. A new comparison tool needs a person's review: list
  it in your report.
- Never print the token that `chaceon-clone` uses.
