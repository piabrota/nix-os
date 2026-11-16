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

  # Live metrics (metrics.nix, docs/METRICS.md): the collector, and the one location that lets
  # piabrota2's address fetch its file. No port, no package of its own.
  piabrota.metrics = {
    name = "piabrota";
    label = "piabrota (KVM 1)";
    collector.enable = true;
    # Up or down for each site of this host, and the commit count of piabrota/nix-os.
    probe.enable = true;
    # The visits of each site in the last 24 h, from a log of the pages browsers got (docs/METRICS.md, "Visits").
    visits.enable = true;
    publish = {
      enable = true;
      allowFrom = [ "187.41.117.18" ];
    };
  };
}
