---
name: rbi
description: "Use when a prompt is unclear or big. Refine, ask, plan."
version: 1.1.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Prompt, Brainstorming, Planning, Delegation, Workflow]
    related_skills: [hermes-omp, hermes-rig, kvm4-health, ponytail-review, ptbr, ste100]
---

# rbi: refine before implementing

The owner types fast. A prompt can have typing errors, ideas stuck together, a missing reason, or a
mix of a brainstorm, a plan and a task. `/rbi <prompt>` cleans the prompt, finds out what he
wants, plans the work for the shortest run time, and then does the work. The command widens no
permission: the deny list, SOUL.md and the other skills still hold.

## Flags

Flags can stand anywhere in the prompt as a word of their own. Remove them before you refine.
Another `--word` stays in the text. With no text, use the owner's last message.

- `--dry`: stop after the plan, and say what you would do next.
- `--go`: the owner opts out of the questions. State each choice you make in one line and go on.
  The gate for a project and the `Needs your yes` rule still hold.
- `--pt`: ponytail is on (see the last section). Without this exact flag it is off, and the word
  "ponytail" in a prompt does not turn it on.

## 0. Know what you know

- Everything that matters is in the request: refine, plan, do the work. Ask nothing.
- Something that changes the result is missing: refine, then follow steps 2 and 3.
- No work in it (a question, a greeting): answer it.

## 1. Refine the prompt

1. Keep the language. For pt-BR follow the `ptbr` skill: an explicit subject, one idea in each
   sentence, whole words, the 1990 spelling. For English text that goes into a pull request, follow
   `ste100`.
2. Fix spelling, accents, punctuation and agreement. Keep his words and his meaning.
3. Put one idea on each line, under these labels. Leave out an empty label.
   - **Goal**, **Context** (only facts he gave), **Constraints**, **Deliverable**.
   - **Done when**: one check that proves it. If he gave none, write one and mark it `assumed:`.
   - **Open points**: a question whose answer changes the result.
   - **Needs your yes**: a step that spends money, writes outside your own state, contacts other
     people, merges, deploys, changes a workflow or cannot be undone.
4. Name the mode of each part: `brainstorm` (ideas, no file changes), `plan` or `build`. Split a
   prompt that mixes modes into tasks, in his order. Show `ponytail: on` or `off`.
5. Mark each guess `assumed:`. Add no fact, name, number or goal that he did not give.
6. Show the refined prompt, then at most three lines on what you changed.

## 2. Look before you ask

When he named files, a repository, a PR or an earlier thread, read them first, and the code or
notes they connect to, until you can say how the parts work now and what the change touches. Never
ask what the project or his words already answer, and never reopen what he decided. Say what you
looked for and what you found.

## 3. Talk, when something is open

1. **First message**, about 200 words: say his request back in your words (what he wants, for whom,
   why, as far as he said it) and what you found. If you found a conflict or a cheaper path, say so
   plainly. Then ask one question.
   - He gave no reason: ask one open question in his terms, with no options. Say what the answer
     would change.
   - He gave a reason: ask the question whose answer changes the result most. If you can name the
     choices, sketch each with its trade-off and say which you pick.
   - Nothing is open: end with the short design and ask for a yes.
   - End with one line: "Or say `--go` and I do it with my picks."
2. **One question at a time.** Make it specific, and build it on his last answer or on what you
   found. A proposal he can correct, with your reason, often beats a question. A default is fine if
   you say it aloud.
3. **Lay out the approaches** in a message of their own, before any design: two or three real
   alternatives, with what each trades off, and your pick. Drop the weak ones. If one way is
   sensible, say so and say why the others do not fit.
4. **Play back** in 100 to 200 words each time one part is settled. Only his words go in as his.
   Mark yours `proposal:`. End with "what is wrong or missing?".
5. **Spike.** A quick throwaway build in `~/.hermes/cache/scratch` can be the cheapest way to
   learn. Offer it, and label it throwaway. To keep it is a new request.
6. **Show in text.** Sketch a layout, a flow or a table as a few lines. No browser tool is used.
7. **Size the work.** A small change gets a short design in the message: the approach, why, the
   checks. A project gets a design file `omp-tasks/<a-few-words>-design.md`: intent and why, goals,
   non-goals, constraints, the approaches and the pick, what he decided, what is left to the
   builder. For several independent projects, agree an order and do one at a time.
8. **Read it as the builder** before you hand it over. Sort each open point: answered by the
   conversation, minor (your call, marked in the file), or his. Bring his in one message, the most
   important first.

**Gate.** For a project, build nothing until he says yes to the design. For a small change, state
the design and go on, unless an open point or `Needs your yes` has a line. Reading is always fine.
`--go` removes the gate for a project, but not `Needs your yes`. Ask at most once for a task, in
one message with every question, using `clarify`, and stop.

## 4. Plan for run time

List the steps: who does each, what it needs, what it gives, and which step it waits for. Find the
longest chain (the critical path) and start every step that does not wait, together.

| Step | Who |
|---|---|
| One grep, file search, list, count or fetch | You |
| A decision, a diff to write, a claim to judge | You. Never a subagent |
| Three or more independent read-only tasks, or more than about 20 files | Subagents (Haiku), at most two together. Check what they return |
| A change to code, config or a script | `omp`, through `hermes-omp`. At most two runs together |
| Markdown with no code, or a small slip in an omp diff | You, by hand. Say so |
| A merge, an approval, a push outside `hermes/*`, a deploy, a file in `.github/workflows/` | The owner. Give a draft or the exact text |

1. Before a large clone, a long omp run or many subagents, run `kvm4-health` and read `units`.
2. Tell the owner when an omp run starts. Start none from cron or from a subagent.
3. A subagent starts with no context: give it everything, and a schema for its answer.
4. A merge to piabrota/nix-os deploys. A change in `hermes.nix` restarts `hermes-agent`, and one in
   `openrig.nix` restarts `openrig`. Ask the owner to merge nothing while a run is active.
5. State the cost in words: omp runs, subagents, low, medium or high. A dollar figure only if you
   measured it.

```
Plan (critical path: 1 > 3 > 4)   ponytail: off
1. [me]        read the two files      needs: none  gives: the facts
2. [subagents] read 24 pages           needs: URLs  gives: notes per page
3. [omp]       write the change        needs: 1     gives: a diff
4. [me]        review the diff         needs: 3     gives: a verdict
Parallel: 1 and 2. Cost: one omp run, two subagents, medium.
```

## 5. Implement

1. Follow the plan. The design file, if there is one, is the base of the omp task file: add the
   usual lines of `hermes-omp` (checks, "How to prove it is done", no commit, no push).
2. Check each step with a command or a file read, not with what a subagent or omp says of itself.
3. If a step fails, say so, fix the cause and check again. If it still fails, stop and report. Never
   replace a real result with a made-up one.
4. Finish with what changed, what is verified, and what is left, in the voice of SOUL.md.

## `--pt`: ponytail, opt-in

Ponytail is the owner's skill `ponytail-review`: correct, safe, holds under load, tested, fast and
lean, and every line is needed. It acts only when the flag is in the prompt and the plan has an
omp step. A plan with no omp step: say that `--pt` had nothing to act on.

1. **Implement run.** Add a section "Ponytail" to the task file: the order above; add no line that
   is not needed; reuse a helper that the repository has; prefer the standard library to a new
   dependency; no abstraction with one use; no option that nobody sets; a deliberate shortcut gets
   a `shortcut:` comment that names its limit.
2. **Review run**, after the first run and your own check, read-only (`--approval-mode write`, as
   `hermes-omp` says for reviews). The task file gives the path of the skill (`skill_dir` in the
   output of `skill_view("ponytail-review")`, a store path that omp can read), the diff to review,
   and "edit nothing". Ask for the numbered findings and the verdict of the skill.
3. **Check** each Must fix finding yourself with a grep or a file read. For each confirmed one, run
   one fix run as `hermes-omp` says in "A review that fixes the code", then run the checks again.
4. Show the owner the findings, which you confirmed and which you only relay. Say that `--pt` added
   one or two omp runs. It is his yes to a third run for the task.

## Red flags

| Thought | Reality |
|---|---|
| "I will list what he might want" | Options steer. Ask him to describe it first. |
| "I will fill in sensible defaults" | Good. Say them aloud, so he can reject them. |
| "He said it sounds good, so I build" | A yes covers what you showed him. An unwritten design is not approved. |
| "The spike works, so I keep building" | To keep it is a new request. Back through the gate. |
| "He wrote the word ponytail" | Only `--pt` turns it on. |

## Credit

The talking steps (look first, one question at a time, approaches, play back, size, the gate, the
spike) follow the `brainstorming` skill of obra/superpowers (MIT). The rest is this repository's.
