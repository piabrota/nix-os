package piabrota.reels

import piabrota.lib.Command

/** The commands of reels/: the toolkit of the Reels Fabric rig. */
val commands: List[Command] = List(
  Command("reel", "the Reels Fabric toolkit: screenplay, gate, scenes, sound, render, QA, publish", Reel.main),
)
