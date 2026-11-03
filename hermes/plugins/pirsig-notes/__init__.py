"""pirsig-notes: smart notes from a chat, as a pull request to the pirsig brain."""

from functools import partial
from pathlib import Path

from . import tools


def register(ctx):
    ctx.register_tool(name="pirsig_note_search", toolset="pirsig", schema=tools.SEARCH,
                      handler=partial(tools.search, ctx=ctx))
    ctx.register_tool(name="pirsig_notes_submit", toolset="pirsig", schema=tools.SUBMIT,
                      handler=partial(tools.submit, ctx=ctx))
    skill = Path(__file__).parent / "skills" / "smart-notes" / "SKILL.md"
    ctx.register_skill("smart-notes", skill)
