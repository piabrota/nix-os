# piabrota: the Hostinger KVM 1 VPS (1 vCPU, 4 GB RAM, 50 GB disk), the first host. It serves the
# public web (www.piabrota.art and the Loco apps on it). Until kvm4 is live it also runs Hermes,
# with the KVM 1 limits, and PGX; then those lines go and this box keeps the web only
# (docs/DEPLOY.md, "A second host").
{ ... }:
{
  imports = [
    ../../configuration.nix
    ../../apps.nix
    # Hermes Agent, Nous Research's agent, on the chat platforms it has tokens for (docs/HERMES.md),
    # cut for KVM 1 (./hermes.nix).
    ../../hermes.nix
    ./hermes.nix
    # Its write access to GitHub, as its own App: hermes/* branches and pull requests only.
    ../../hermes-github.nix
  ];

  # The name Hostinger gave the VPS. Without it NixOS writes `nixos` to /etc/hostname, and cloud-init,
  # which set srv2108887 on the first boot, keeps whatever /etc/hostname says on the next ones
  # ("assuming user maintained hostname"): the 2026-10-31 reboot came up as `nixos`. This keeps the
  # two in step.
  networking.hostName = "srv2108887";

  # The static site on www.piabrota.art (site.nix). DNS points both names at this box.
  piabrota.site.enable = true;
  # PGX, a Postgres instead of a PostgreSQL server or Docker (pgx.nix, docs/PGX.md). Not for data
  # you keep: that stays in SQLite.
  piabrota.pgx.enable = true;
}
