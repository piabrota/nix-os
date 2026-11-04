# omp, the default coding worker: see it, tune it

Portuguese: [HERMES-OMP.ptBR.md](HERMES-OMP.ptBR.md) (written first; this file mirrors it).

## The rule

Every task that writes or reviews code, config or scripts goes through omp (oh-my-pi). Hermes
writes a task file and runs omp. Hermes reads the diff. Then Hermes commits, pushes a `hermes/*`
branch and opens the pull request.

Hermes does not write code with its own file tools. omp never pushes and never calls `gh`.

Hermes edits by hand in two cases only: a Markdown file with no code, and a small slip in omp's
diff. In the second case Hermes says so in chat. omp does not run for chat, notes or research.

The procedure is the `hermes-omp` skill: [`hermes/skills/hermes-omp/SKILL.md`](../hermes/skills/hermes-omp/SKILL.md).
The setup is in [HERMES.md](HERMES.md#omp-the-coding-worker). The skill is also a command:
`/hermes-omp` on Telegram and `/skill` on Discord.

## What you see in chat

Before the run, Hermes tells you the repository, the branch, the mode (write or review only), the
task file, the models and the thinking level.

While the run goes on, Hermes tells you the state of the process and the time left. The output of
omp stays empty until the run ends.

After the run, Hermes tells you these facts:

- the files omp changed;
- the checks omp ran, and the checks Hermes ran;
- what nobody verified, and each "unsure" label that omp wrote;
- the run time;
- the link to the pull request.

omp keeps each session in `~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<sessionId>.jsonl`, under
Hermes's home. The command `omp --export <session>` writes a session as HTML (omp docs `session.md`
and `cli-reference.md`). Not tried on this box.

## The layers: what you can edit

The rows go from the nearest layer to the farthest layer.

|Layer|File|What it controls|Who changes it|When it takes effect|
|---|---|---|---|---|
|1. The task|`/var/lib/hermes/workspace/omp-tasks/<name>.md` (a temporary file)|The goal, the done criteria, the check commands, the files to start from|You, when you ask Hermes in chat|The next run, no deploy|
|2. Flags of one run|The `omp` command in the skill|`--thinking <level>`, `--model <id-or-role>`, `--max-time`|You, when you ask Hermes ("run omp with --thinking max")|The next run, no deploy. Use only model, thinking and time flags: never a flag that loosens a rule|
|3. The rules of the target repository|`AGENTS.md`, `.omp/AGENTS.md`, `.omp/RULES.md` in the repository that omp changes|The project background (`AGENTS.md`) and the short hard requirements that stay in every request (`RULES.md`)|A PR to that repository|After the merge there|
|4. The procedure|[`hermes/skills/hermes-omp/SKILL.md`](../hermes/skills/hermes-omp/SKILL.md)|When Hermes uses omp, the shape of the task file, the diff review, what Hermes tells you|A PR to nix-os|After the next deploy (see below)|
|5. The prompt addition|[`hermes/omp-append-system.md`](../hermes/omp-append-system.md)|The rules that the wrapper appends to omp's system prompt: small diffs, a stated check, no "done" without output|A PR to nix-os|After the next deploy (see below)|
|6. The settings overlay|[`hermes/omp.yml`](../hermes/omp.yml)|The models per role, the thinking level, the tools, the memory, the bash deny rules, the restricted folders|A PR to nix-os|After the deploy|
|7. The wrapper|`ompWrapped` in [`hermes.nix`](../hermes.nix)|The environment, `choom`, and the flags that every run gets|A PR to nix-os|After the deploy|
|8. The version|[`omp/package.nix`](../omp/package.nix) (tag `v18.16.0`)|The omp release|A PR to nix-os|After the deploy|

`deploy.yml` ignores a merge that changes only Markdown. That includes the Markdown files under
`hermes/`: `SOUL.md`, `AGENTS.md`, `omp-append-system.md` and the skill. Such a change reaches the box
with the next deploy, or when you run `deploy.yml` by hand on `main`. A merge that changes a `.nix`
file, `hermes/omp.yml` or another file that is not Markdown deploys the box.

The wrapper runs omp under `timeout`. No run lives more than 35 minutes, whatever flags the caller
gives. A restart of the gateway also stops a run. For a long task, the task file names a progress
file (`omp-tasks/<name>.progress`). omp appends one line after each finished step, and a new run
continues after the last one. `kvm4-health` reports `NRestarts` of each unit: WARN above 3, CRIT
above 50.

## Which setting wins

This is the order in omp, highest first (omp docs `config-usage.md`, "Layers", at v18.16.0):

1. an environment variable that a setting declares;
2. runtime overrides;
3. overlays: `PI_CONFIG_FILES` first, then each `--config <file>`; a later file wins;
4. the project's `.omp/config.yml`;
5. the user's `~/.omp/agent/config.yml`;
6. the default of omp.

On this box the wrapper sets `PI_CONFIG_FILES` to `hermes/omp.yml`. That file is in the read-only
store. So the `.omp/config.yml` of a repository and the `~/.omp/agent/config.yml` of Hermes cannot
loosen it. An array in the overlay replaces the array of a lower layer.

## Recipes: what to change for what

- **Better code, more reasoning.** Change `defaultThinkingLevel` in `hermes/omp.yml`. The accepted
  values are `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` and `auto`. Today it is `high`.
  For one run, use `--thinking`. The cost is more of your Claude quota.
- **A stronger or cheaper model for one job.** Change `modelRoles.<role>` in `hermes/omp.yml`.
  The roles `default`, `slow` and `plan` carry the main work. The role `task` is the subagent role
  that edits code. The roles `smol`, `tiny`, `commit`, `memory`, `advisor` and `judge` are cheap side
  roles. Today the first four use Sonnet and the others use Haiku. Use only `anthropic/...` models:
  your subscription is the only provider.
- **Better results for one repository.** Write `.omp/RULES.md` (short, hard rules) and
  `.omp/AGENTS.md` (background) in that repository.
- **Better results for one task.** Write a better task file. Name the done criterion and the exact
  check commands.
- **A different habit for every run.** Edit `hermes/omp-append-system.md`.
- **When Hermes uses omp, or what it tells you.** Edit the skill.
- **Longer runs.** Change `--max-time` in the command of the skill (today 15 minutes). Change
  `tools.maxTimeout` in `hermes/omp.yml` too.
- **Language servers.** Set `lsp.enabled` in `hermes/omp.yml`. It is off today to save memory. Try it
  only with a measured memory peak (`systemctl show hermes-agent -p MemoryPeak`).

## Try a change on your own computer first

1. Install omp v18.16.0 from the release page of `can1357/oh-my-pi` (file `omp-linux-x64`).
2. In a clone of nix-os, run `omp --config hermes/omp.yml --config my.yml`.
3. Put in `my.yml` only the keys that you test. The later file wins.

Test only model and thinking keys this way. A second overlay can loosen the deny rules by accident.
Never copy a change of `bash.patterns` or `restrictedFolders` from an experiment. Not tried on
this box. What you test on your computer does not change the box. Only a merge does.

## What stays fixed

omp cannot push, call `gh`, install packages, or use `sudo`, `curl` or `wget`. omp cannot read the
secrets or the state of Hermes. These rules are in `hermes/omp.yml` (`bash.patterns` and
`tools.restrictedFolders`). The file is in the store, and neither Hermes nor omp can edit it.

To loosen a rule is your decision, made in a PR to nix-os. This doc does not recommend it.

## Not checked

- The `omp --export` command on the box.
- The `--config` experiment on your computer.
- The memory peak of a run with a higher thinking level.

## Sources

The omp docs at the tag v18.16.0, in [github.com/can1357/oh-my-pi](https://github.com/can1357/oh-my-pi)
(MIT): `docs/settings.md`, `docs/config-usage.md`, `docs/cli-reference.md`,
`docs/context-files.md`, `docs/skills.md` and `docs/session.md`.
