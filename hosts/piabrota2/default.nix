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
}
