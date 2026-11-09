# piabrota2: the Hostinger KVM 4 VPS (4 vCPU and 16 GB RAM by Hostinger's plan list; `just remote-specs`
# gives the real figures), the second host. It runs Hermes: the full Hermes (upstream's `full`
# package and upstream's defaults), its GitHub App, its web dashboard on hermes.piabrota.art, PGX
# and OpenRig, which Hermes operates. Paperclip is off for now (see below). It does not serve
# www.piabrota.art: that name points at piabrota.
#
# Its setup from an empty VPS is docs/DEPLOY.md, "A second host"; the move of Hermes from piabrota
# is docs/MIGRATION-KVM4.md. Nothing is cloned or built on the VPS.
{ ... }:
{
  imports = [
    ../../configuration.nix
    ../../hermes.nix
    ../../hermes-github.nix
    # The dashboard behind nginx, TLS and basic auth. hermes.piabrota.art must point at this box.
    ../../hermes-web.nix
    # Paperclip, off for now: the import stays, so `enable = true` below turns it back on.
    # paperclip.piabrota.art must point at this box before that.
    ../../paperclip.nix
    # OpenRig (openrig.nix): loopback only, no DNS, no port.
    ../../openrig.nix
    # The room (piabrota/room) on room.piabrota.art, which must point at this box.
    ../../room.nix
    # The HTML pages of h0ffmann/proof and piabrota/pirsig on proof.piabrota.art, which must point
    # at this box.
    ../../proof.nix
  ];

  # piabrota2 is the VPS name in hPanel; Hostinger first named it srv2125808 (srv2125808.hstgr.cloud
  # stays its address). Without this line NixOS writes `nixos` to /etc/hostname; see
  # hosts/piabrota/default.nix.
  networking.hostName = "piabrota2";

  # Far above what Hermes used on piabrota (1G and CPUWeight 50), so a runaway task cannot starve
  # sshd and make a deploy roll back: half the RAM, and half the CPU share of other units when the
  # four cores are busy. The dashboard has its own 2G (hermes-web.nix).
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = "8G";
    CPUWeight = 50;
  };

  piabrota.hermesWeb.enable = true;
  piabrota.pgx.enable = true;
  # Off since 2026-11-04 by the owner's order; docs/PAPERCLIP.md says how to turn it on.
  piabrota.paperclip.enable = false;
  # Hermes operates it with `rig` and the skill hermes-rig; docs/OPENRIG.md.
  piabrota.openrig.enable = true;
  # The web UI at rig.piabrota.art, behind the dashboard's login (docs/OPENRIG.md, "The web UI").
  piabrota.openrig.web.enable = true;
  piabrota.openrig.web.domain = "rig.piabrota.art";
  # The rigs wave-forecaster-dev and wave-forecaster-dev-integrate: the seats' Rust tools, their
  # folders, the outbox and a read-only token for h0ffmann/chaceon (docs/OPENRIG.md). Off: the
  # specs are in /etc/openrig/specs as a definition only. The owner turns this on to use them.
  piabrota.openrig.waveForecaster.enable = false;
  # The 3D room, piabrota/room at a pinned commit (room-site/default.nix), at room.piabrota.art.
  piabrota.room.enable = true;
  # The same room on grid.piabrota.art, opened on its ▲ grid view (room.nix). The name must point
  # at this box.
  piabrota.room.grid.enable = true;
  # Every HTML page of h0ffmann/proof and piabrota/pirsig at pinned commits, with an index
  # (proof-site/default.nix), at proof.piabrota.art.
  piabrota.proof.enable = true;
  # Live metrics (metrics.nix, docs/METRICS.md): the page at metrics.piabrota.art, which must point at
  # this box, this host's own collector, and the pull of piabrota's file.
  piabrota.metrics = {
    name = "piabrota2";
    label = "piabrota2 (KVM 4)";
    collector.enable = true;
    web.enable = true;
    pull = {
      enable = true;
      url = "https://www.piabrota.art/_metrics/piabrota.json";
    };
  };
}
