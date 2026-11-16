# The piabrota sites, in ONE place. The brand bar and the footer of every page that wears the kit
# (scala/design/Kit.scala) list `sites` with `access = "public"`; a `login` site is listed here and
# kept out of the nav. `host` is the nginx virtual host that serves the site: `www` and `figures` share one.
# `checks.design-sites` (flake.nix) fails when a virtual host under piabrota.art is in neither `sites`
# nor `hidden`, or when a site names a host that no system serves. A new site starts here.
{
  sites = [
    { id = "www"; label = "www"; url = "https://www.piabrota.art/"; host = "www.piabrota.art"; line = "The site: what piabrota is, its projects, its board and its partners."; access = "public"; }
    { id = "skills"; label = "skills"; url = "https://skills.piabrota.art/"; host = "skills.piabrota.art"; line = "Skills for agents, from piabrota/skills."; access = "public"; }
    { id = "figures"; label = "figures"; url = "https://www.piabrota.art/figures/"; host = "www.piabrota.art"; line = "How piabrota works, drawn with archify, in English and pt-BR."; access = "public"; }
    { id = "proof"; label = "proof"; url = "https://proof.piabrota.art/"; host = "proof.piabrota.art"; line = "Every HTML page of h0ffmann/proof: specifications, Z3 reports and diagrams."; access = "public"; }
    { id = "pirsig"; label = "pirsig"; url = "https://pirsig.piabrota.art/"; host = "pirsig.piabrota.art"; line = "The video notes and the figures of piabrota/pirsig, the second brain."; access = "public"; }
    { id = "wave"; label = "wave"; url = "https://wave.piabrota.art/"; host = "wave.piabrota.art"; line = "The WW3 GPU Lab: WAVEWATCH III on Kokkos and CUDA, its decisions, designs and lineage."; access = "public"; }
    { id = "closed"; label = "closed"; url = "https://closed.piabrota.art/"; host = "closed.piabrota.art"; line = "The god that failed: a book on why closed source failed as a protection, from h0ffmann/closed-source."; access = "public"; }
    { id = "hffmnn"; label = "hffmnn"; url = "https://hffmnn.piabrota.art/"; host = "hffmnn.piabrota.art"; line = "Matheus Hoffmann: what he thinks, writes, reads and plays, from h0ffmann/h0ffmann."; access = "public"; }
    { id = "room"; label = "room"; url = "https://room.piabrota.art/"; host = "room.piabrota.art"; line = "piabrota/room: a 3D room with camera shots, a VCR, a window on Rio and piabrota RADIO."; access = "public"; }
    { id = "grid"; label = "grid"; url = "https://grid.piabrota.art/"; host = "grid.piabrota.art"; line = "The room on its own name, opened on the grid: the Brazilian coast on triangles."; access = "public"; }
    { id = "metrics"; label = "metrics"; url = "https://metrics.piabrota.art/"; host = "metrics.piabrota.art"; line = "Processes, memory and vCPU of both hosts, read every 10 seconds."; access = "public"; }
    { id = "hermes"; label = "hermes"; url = "https://hermes.piabrota.art/"; host = "hermes.piabrota.art"; line = "The Hermes dashboard. It needs the login."; access = "login"; }
    { id = "rig"; label = "rig"; url = "https://rig.piabrota.art/"; host = "rig.piabrota.art"; line = "The OpenRig web UI. It needs the login."; access = "login"; }
  ];

  # Hosts under piabrota.art that are not sites: the apex only redirects to www.
  hidden = [ "piabrota.art" ];
}
