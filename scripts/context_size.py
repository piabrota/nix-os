#!/usr/bin/env python3
"""Check the size of the files Hermes loads into its context: AGENTS.md, hermes/AGENTS.md and
hermes/SOUL.md. Read-only. Hermes cuts a file that is too long and keeps only its head and tail,
so the middle, here the safety rules, never reaches the model.

  python3 scripts/context_size.py      (or: just context-size)

Exit 0 when every file is ok or WARN, 1 when a file is over the limit.
"""

import os
import sys
from pathlib import Path

# Hermes cuts a context file at 32000 characters (agent.prompt_builder logs 'Context file X
# TRUNCATED') and drops the middle. Warn from a margin of 2000.
LIMIT = 32000
WARN = 30000
FILES = ["AGENTS.md", "hermes/AGENTS.md", "hermes/SOUL.md"]


def level(n):
    if n > LIMIT:
        return "FAIL", f"{n} / {LIMIT}: Hermes drops the middle"
    if n > WARN:
        return "WARN", f"{n} / {LIMIT} (margin {LIMIT - WARN})"
    return "ok", f"{n} / {LIMIT}"


def main(root):
    status = 0
    for f in FILES:
        path = root / f
        if not path.is_file():
            continue
        lvl, text = level(len(path.read_text(encoding="utf-8")))
        print(f"{lvl:<5} {f}  {text}")
        if lvl == "FAIL":
            status = 1
        if os.environ.get("GITHUB_ACTIONS") and lvl != "ok":
            kind = "warning" if lvl == "WARN" else "error"
            print(f"::{kind} file={f}::{f} {text}")
    return status


if __name__ == "__main__":
    sys.exit(main(Path(__file__).resolve().parent.parent))
