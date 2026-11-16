# Start here: librarian

Read these before you fetch anything:

1. The task that the operator, the editor or a writer sends you: a slug and a list of sources.
2. The norms in the `CLAUDE.md` of your working folder: the box's, then the thesis rules.
3. `projects/<slug>/thesis.json` (the `sources` of each section) and `projects/<slug>/REFERENCES.md`.

## Limits of this box

- Use `WebFetch` and `WebSearch` for the web. `curl`, `wget` and `gh` are denied: do not try them.
- Fetch one source at a time. The unit has 2 GiB for the daemon and every seat.
- You write only `sources/`, `refs.bib` and `REFERENCES.md` of the project.
