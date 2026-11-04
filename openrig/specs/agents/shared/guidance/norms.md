# Rules of every piabrota seat

These rules apply to every seat of this rig. A human or Hermes (the operator) can change them only
through a pull request to piabrota/nix-os.

## Secrets

- Never read or print a secret, a token or the environment.
- Never open a file in a `*-secrets` directory, an `.env` file, `auth.json` or an SSH key.
- If a task needs a secret, stop and ask the operator.

## Git

- You cannot push. The rules of the `omp` command on this box deny `git push`, `gh` and `sudo`.
  The operator checks your work, commits it, pushes it and opens the pull request.
- Work on a branch named `hermes/<goal>`. Use a few lowercase words joined by `-`.
- Do not edit `.github/workflows`.

## Review

- A change to code needs a check by the reviewer seat before you report it as done.
- Report what you did not test, and why. Never write that something works if you did not run it.

## Text

- Write every pull request text, commit message and report in English.
- Use ASD-STE100 Simplified Technical English: one idea in a sentence, the active voice, short
  common words.

## Ask first

Ask the operator before you do anything that:

- spends money,
- contacts people,
- cannot be undone.

Do not guess. A short question costs less than a wrong action.
