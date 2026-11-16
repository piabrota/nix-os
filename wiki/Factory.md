# Factory

[Português](Fabrica)

The open software factory behind piabrota. [OpenRig](https://github.com/mvschwarz/openrig) is its
engine: it will automate the SDLC (the software development life cycle). This page says what exists
today and what has not run yet. The full guide is
[`docs/OPENRIG.md`](https://github.com/piabrota/nix-os/blob/main/docs/OPENRIG.md).

## What it is

One rig, `piabrota-dev`, with two seats on `omp`: `dev-builder` and `dev-reviewer`. OpenRig runs on
`piabrota2` as the unit `openrig` (loopback only, `MemoryMax=2G`). Its UI is at rig.piabrota.art, behind
basic auth. Hermes operates the rig with the `rig` CLI and the skill `hermes-rig`. The figure is on
[Architecture](Architecture).

## The stages

| Stage | Who does it | State |
|---|---|---|
| Idea and triage | The owner, with the skills `/triage` and `/mip` | Today |
| Build | The builder seat | Next: the seat has not run a task |
| Review | The reviewer seat | Next: the seat has not run a task |
| Pull request | Hermes, on a `hermes/*` branch, in ASD-STE100 Simplified Technical English | Today, after a run of `omp` by Hermes |
| Merge | A human, always | Today |
| Deploy | `deploy.yml`: deploy-rs and magic rollback | Today |
| Watch | `kvm4-health`, the watchers and the daily VPS check | Today |

## The status today

- OpenRig 0.7.7 runs on `piabrota2`, and its UI is on.
- The rig is specified in `openrig/specs/rigs/piabrota-dev/rig.yaml`. Both seats run without approval
  prompts (`permission_policy: builtin:yolo`, the owner's decision). They use the owner's Claude
  subscription.
- Hermes does not start seats from cron.
- **The seats are idle.** No task has gone through the builder and reviewer loop yet.
- Today Hermes makes a pull request by running `omp` itself (the skill `hermes-omp`). Then it checks
  the diff, commits, pushes a `hermes/*` branch and opens the pull request. A human merges. A merge to
  `main` deploys.

## How a task will go through

1. The owner gives Hermes a task. Hermes writes it as the skill `hermes-omp` says.
2. Hermes checks `kvm4-health` and `rig status`, starts the rig (`rig up`) and sends the task to the
   builder seat (`rig send`).
3. The builder writes and tests the change in its own clone. It asks the reviewer to check the diff (the
   edge `delegates_to`).
4. The reviewer checks the diff by evidence and answers.
5. Hermes reads the answer and checks the diff itself. Then it commits, pushes a `hermes/*` branch and
   opens the pull request. The seats cannot push.
6. A human reviews and merges. The merge deploys.

Steps 2 to 5 will run this way. They have not run yet.

## The guardrails that stay

- Humans merge. No seat and no agent merges.
- The deny list of Hermes and `hermes/omp.yml` stay in force. A seat cannot push: `omp.yml` denies
  `git push`, `gh` and `sudo`.
- No secret in a spec, a task or a message.
- At most two seats at the same time.
- The UI is behind basic auth and TLS. It has a terminal for each seat: see [Operations](Operations).

## What is next, and what is not proved

- **Next.** Send the first real task through the builder and the reviewer, and compare the result with
  a run of `omp` by Hermes. Then decide if Hermes sends all code tasks to the rig.
- **Not proved.** A task through the whole loop. The messages between the two seats. A pull request that
  starts from a seat's diff.
