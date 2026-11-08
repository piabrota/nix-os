---
name: rbi
description: "Use when a prompt is messy. Refine, plan, then build."
version: 1.0.0
author: piabrota
license: MPL-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Prompt, Planning, Delegation, Workflow]
    related_skills: [hermes-omp, hermes-rig, kvm4-health, ptbr, ste100]
---

# rbi: refine before implementing

The owner types fast. A prompt can have typing errors, ideas stuck together, or a mix of a
brainstorm, a plan and a task. Run `/rbi <prompt>` to clean the prompt first, plan the work for the
shortest run time, and then do the work. The command widens no permission: the deny list, SOUL.md
and the rules of the other skills still hold.

Start the words with `dry` (`/rbi dry <prompt>`) to stop after the plan. With no text after the
command, use the owner's last message.

## 1. Refine the prompt

1. Keep the language of the prompt. For pt-BR, follow the `ptbr` skill: an explicit subject, one
   idea in each sentence, whole words, the 1990 spelling. For English text that goes into a pull
   request, follow `ste100`.
2. Fix spelling, accents, punctuation and agreement. Keep his words and his meaning.
3. Put one idea on each line. Group the lines under these labels, and leave out an empty label:
   - **Goal**: the result he wants.
   - **Context**: facts he gave. Add no fact, name, number or goal that he did not give.
   - **Constraints**: what the work must keep or avoid.
   - **Deliverable**: the file, the PR, the message or the answer.
   - **Done when**: one check that proves the work is done. If he gave none, write one and mark
     it `assumed:`.
   - **Open points**: a question whose answer changes the result.
   - **Needs your yes**: a step that spends money, writes outside your own state, contacts other
     people, merges, deploys, changes a workflow or cannot be undone.
4. Name the mode of each part: `brainstorm` (ideas only, no file changes), `plan` (a plan for him
   to read) or `build` (change something). When the prompt mixes modes, split it into tasks in
   the order he wrote them.
5. Mark each guess `assumed:`. Never present a guess as a fact.
6. Show the refined prompt. Then show at most three lines on what you changed, for example
   "fixed 4 typing errors; split 2 ideas; added one `Done when`".

## 2. Plan for run time

Write the steps as a list. For each step give: who does it, what it needs, what it gives, and
which step it waits for. Then find the longest chain of steps (the critical path), and start every
step that does not wait, at the same time.

Choose who does each step with these rules:

| Step | Who |
|---|---|
| One grep, file search, list, count or fetch | You, directly |
| A decision, a diff to write, or a claim to judge | You. Never a subagent |
| Three or more independent read-only tasks, or a read of more than about 20 files | Subagents (Haiku), at most two at the same time. Check what they return |
| A change to code, config or a script | `omp`, through the `hermes-omp` skill. At most two runs at the same time |
| Markdown with no code, or a small slip in an omp diff | You, by hand. Say so |
| A merge, an approval, a push outside `hermes/*`, a deploy, a file in `.github/workflows/` | The owner. Give him a draft or the exact text |

Add these checks to the plan:

1. Before a large clone, a long omp run or many subagents, run `kvm4-health` and read the `units`
   lines.
2. Tell the owner when an omp run starts. Start no omp run from a cron job or from a subagent.
3. A subagent starts with no context. Give it everything it needs, and a schema for its answer.
4. A merge to piabrota/nix-os is a deploy. A change in `hermes.nix` restarts `hermes-agent`, and a
   change in `openrig.nix` restarts `openrig`. Ask the owner to merge no pull request while a run
   is active.
5. State the cost in words: how many omp runs, how many subagents, and whether it is low, medium
   or high. Give a dollar figure only if you measured it.

Show the plan in this form:

```
Plan (critical path: 1 > 3 > 5)
1. [me]        read the two files          needs: none        gives: the facts
2. [subagents] read 24 pages of a site     needs: the URL list gives: notes per page
3. [omp]       write the change            needs: 1           gives: a diff
4. [me]        review the diff             needs: 3           gives: a verdict
Parallel: 1 and 2. Cost: one omp run, two subagents, medium.
```

## 3. Gate

1. If `Needs your yes` has a line, or an open point changes the result, ask in one message with
   `clarify` and stop. Ask at most once for a task, and put every question in that one message.
2. Otherwise go on at once. Do not wait for a reply to the refined prompt.
3. With `dry`, stop here and say what you would do next.

## 4. Implement

1. Follow the plan. After each step, check the result with a command or a file read, not with
   what a subagent or omp says about itself.
2. If a step fails, say so, fix the cause and check again. If it still fails, stop and report
   the failure. Never replace a real result with a made-up one.
3. Finish with what changed, what is verified, and what is left. Follow the voice rules of
   SOUL.md. A good result starts with the words `piou a melhoria`.

## Limits

- The refine step does not change the owner's goal. If the refined prompt differs from his
  meaning in a way that matters, he corrects it in one line and you follow that line.
- The skill does not read secrets and does not start a rig seat, a cron job or a deploy by itself.
- A prompt with no work in it (a question, a greeting) needs no plan. Answer it.
