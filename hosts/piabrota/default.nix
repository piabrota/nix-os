# piabrota: the Hostinger KVM 1 VPS (1 vCPU, 4 GB RAM, 50 GB disk), the first host. It serves the
# public web (www.piabrota.art and the Loco apps on it), and nothing else: Hermes and PGX run on
# piabrota2 (docs/MIGRATION-KVM4.md).
{ ... }:
{
  imports = [
    ../../configuration.nix
    ../../apps.nix
  ];

  # The name Hostinger gave the VPS. Without it NixOS writes `nixos` to /etc/hostname, and cloud-init,
  # which set srv2108887 on the first boot, keeps whatever /etc/hostname says on the next ones
  # ("assuming user maintained hostname"): the 2026-10-31 reboot came up as `nixos`. This keeps the
  # two in step.
  networking.hostName = "srv2108887";

  # The static site on www.piabrota.art (site.nix). DNS points both names at this box.
  piabrota.site.enable = true;

  # Live metrics (metrics.nix, docs/METRICS.md): the agent only. It dials out to the hub on
  # piabrota2 and opens no port. Its limit is 64M (measured: 17 MiB idle); this host has 4 GB.
  piabrota.metrics.agent.enable = true;
  piabrota.metrics.agent.hubUrl = "https://metrics.piabrota.art";
}
