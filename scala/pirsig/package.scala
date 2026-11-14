package piabrota.pirsig

import piabrota.lib.Command

/** The commands of the pirsig brain's tools for Hermes (docs/HERMES-PLUGINS.md). */
val commands: List[Command] = List(
  Command("pirsig-mcp", "the pirsig notes and video tools as one MCP server on stdio, for Hermes", Mcp.run),
)
