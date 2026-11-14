package piabrota.repo

import piabrota.lib.Command

/** The checks of the repository itself, for CI and a checkout. */
val commands: List[Command] = List(
  Command("deepwiki-check", "the DeepWiki page plan (.devin/wiki.json) against DeepWiki's limits", DeepWikiCheck.run),
  Command("figure-lock", "the inputs of each figure of docs/archify/, one line per slug (figures.lock)", Figures.lock),
  Command("figure-check", "every figure has its PNG, shown in the docs or the wiki, and matches its sources", Figures.check),
)
