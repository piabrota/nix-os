# kvm4: the Hostinger KVM 4 VPS (4 vCPU and 16 GB RAM by Hostinger's plan list; `just remote-specs`
# gives the real figures), the second host. It runs everything but the public web: the full Hermes
# (upstream's `full` package and upstream's defaults where KVM 1 cuts them, hosts/piabrota/hermes.nix),
# its GitHub App and PGX. It does not serve www.piabrota.art: DNS points at piabrota, so ACME would
# fail here and the deploy roll back.
#
# Before the first deploy (docs/DEPLOY.md, "A second host"):
# - Install Hostinger's NixOS template on it, as on piabrota: configuration.nix's boot and disk are
#   that template's. If /etc/nixos/hardware-configuration.nix on the box says something else (a
#   disk that is not /dev/sda, no `nixos` label), copy it here and import it.
# - Set networking.hostName below to the name hPanel shows (srvNNNNNNN).
# - Copy Hermes's secrets (/var/lib/hermes-secrets/) from piabrota. While both boxes run Hermes,
#   give this one its own chat bot tokens: one Telegram bot token polled by two gateways gives
#   each a 409 Conflict.
{ ... }:
{
  imports = [
    ../../configuration.nix
    ../../hermes.nix
    ../../hermes-github.nix
  ];

  # Replace with the name Hostinger gave the VPS (see piabrota's file for why it must match).
  networking.hostName = "kvm4";

  piabrota.pgx.enable = true;
}
