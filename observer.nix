# `observer`: an account to look at the box from a coding agent's session, so it can debug without
# a person pasting the output. Key only (keys/observer.pub; the private half stays on the owner's
# computer), no password, no sudo, not a Nix trusted user: it reads, it cannot change the system
# or deploy. systemd-journal lets it read every unit's log; `systemctl status`, `ps`, `free`, `df`
# and the like need nothing more. Hermes's state and the root-only secrets stay out of its reach.
{ lib, ... }:
let
  keys = lib.filter (k: k != "" && !lib.hasPrefix "#" k)
    (lib.splitString "\n" (builtins.readFile ./keys/observer.pub));
in
{
  users.users.observer = {
    isNormalUser = true;
    description = "Read-only access for debugging";
    extraGroups = [ "systemd-journal" ];
    openssh.authorizedKeys.keys = keys;
  };
}
