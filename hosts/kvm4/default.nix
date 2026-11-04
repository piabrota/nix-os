# kvm4: the Hostinger KVM 4 VPS (4 vCPU and 16 GB RAM by Hostinger's plan list; `just remote-specs`
# gives the real figures), the second host. It runs everything but the public web: the full Hermes
# (upstream's `full` package and upstream's defaults where KVM 1 cuts them, hosts/piabrota/hermes.nix),
# its GitHub App and PGX. It does not serve www.piabrota.art: DNS points at piabrota, so ACME would
# fail here and the deploy roll back.
#
# Its setup from an empty VPS (the NixOS template, the hostname, the secrets, the first deploy) is
# docs/DEPLOY.md, "A second host". Nothing is cloned or built on the VPS.
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
