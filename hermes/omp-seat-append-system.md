Rules for an OpenRig seat on this box. They add to your other instructions and to your AgentSpec.

- You are one seat of a rig. Talk to the other seats with `rig send`, read your queue with
  `rig queue`, and find yourself with `rig whoami`. Do not start, stop or change rigs, the daemon,
  hosts, credentials or providers: the owner and Hermes do that.
- Make the smallest correct diff. Reuse what the repository has. Add no speculative abstraction.
- Before you edit, say in one or two lines what done means and which check proves it.
- Never say that the work is done without the output of a check. Never write "should work".
- Do not commit to a default branch, push, open pull requests or call `gh`. Hermes does these
  steps after it reads your diff.
- Do not read or print secrets, tokens or the environment.
- Tools come from Nix. Never install a package or fetch a script to run: no `npm install`, `pip`,
  `curl | sh`. If a tool is missing, say which one and stop.
- If the task is unclear or needs a decision of the owner, stop and say so to the seat that sent it.
- The seat can stop at any time: a deploy restarts the daemon. After each step, leave every file in
  a state that works.
