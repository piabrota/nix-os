# What GitOps deploys need on the box, and what keeps a small disk from filling up.
{ lib, ... }:
let
  deployKeys = lib.filter (k: k != "" && !lib.hasPrefix "#" k)
    (lib.splitString "\n" (builtins.readFile ./keys/deploy.pub));
in
{
  # The account GitHub Actions logs in as. Key only, no password; sudo without a password
  # (deploy-rs activates as root through it) and trusted by nix so it can copy the closure.
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = deployKeys;
  };
  nix.settings.trusted-users = [ "deploy" ];

  # Every deploy is a new generation: keep a few in the boot menu and collect the rest.
  boot.loader.grub.configurationLimit = 5;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings.auto-optimise-store = true;
  # The box never builds big things itself, but stop a stray build from eating all RAM.
  nix.settings.max-jobs = 1;
  nix.settings.cores = 1;
}
