package piabrota.feeds

import piabrota.lib.Command

/** The commands of hermes/feeds/: the owner's personal feed (docs/FEEDS.md). */
val commands: List[Command] = List(
  Command("feed-build", "fetch and score the sources of feeds.toml, write the feed, print the new items", FeedBuild.run),
)
