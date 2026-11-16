package piabrota.thesis

import piabrota.lib.Command

val commands: List[Command] = List(
  Command("thesis", "the toolkit of the wave-forecaster-thesis rig (docs/THESIS.md)", Thesis.run),
)
