package piabrota.design

import piabrota.lib.Command

/** The commands of design/ and proof-site/: build steps of the sites that wear the design kit
  * (docs/DESIGN-KIT.md). `design-inject` and `proof-index` read the kit's CSS from `DESIGN_CSS`.
  */
val commands: List[Command] = List(
  Command("design-inject", "put the brand bar into every page of a folder, or check that it is there", Inject.run),
  Command("proof-manifest", "the list of pages of a built proof or pirsig site, as JSON", ManifestScan.run),
  Command("proof-loc", "the lines of Lean 4, Agda and Z3 code of h0ffmann/proof, as JSON", Loc.run),
  Command("proof-index", "the index page of proof.piabrota.art or pirsig.piabrota.art", Index.run),
  Command("proof-dark-gate", "fail when an archify page sits outside the dark location or ignores ?theme=", DarkGate.run),
)
