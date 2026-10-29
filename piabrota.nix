{ pkgs, ... }:
{
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.h0ffmann = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKO55zOVJexFNARzsHqvJ3bHZFKp/MEetAxksejx/wap hoffmann@poli.ufrj.br" ];
  };

  security.sudo.wheelNeedsPassword = false;
  nix.settings.trusted-users = [ "root" "h0ffmann" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    git
    tmux
    vim
    htop
    curl
    wget
  ];
}
