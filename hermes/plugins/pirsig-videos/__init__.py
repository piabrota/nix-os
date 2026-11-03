"""pirsig-videos: a video's reading and notes, as a pull request to the pirsig brain."""

from functools import partial
from pathlib import Path

from . import tools


def register(ctx):
    for name, schema, handler in (
        ("pirsig_video_fetch", tools.FETCH, tools.fetch),
        ("pirsig_video_check", tools.CHECK, tools.check),
        ("pirsig_video_submit", tools.SUBMIT, tools.submit),
    ):
        ctx.register_tool(name=name, toolset="pirsig", schema=schema,
                          handler=partial(handler, ctx=ctx))
    skill = Path(__file__).parent / "skills" / "video-indexer" / "SKILL.md"
    ctx.register_skill("video-indexer", skill)
