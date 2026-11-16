# The radio's live listeners count (piabrota/room's scripts/listeners.mjs): a small HTTP server
# with no dependency that sends the number of open /live/radio connections over server-sent
# events. It comes from the same pinned commit as the site (room-site/default.nix), so the page
# and its counter always match. For the radio it keeps nothing: no log, no address, no cookie.
# For the room's door it keeps the email a visitor leaves to try the lock (DOOR_FILE, room.nix).
{ callPackage, writeShellApplication, nodejs_22 }:
let
  inherit ((callPackage ./. { })) src;
in
writeShellApplication {
  name = "room-listeners";
  runtimeInputs = [ nodejs_22 ];
  text = ''
    exec node ${src}/scripts/listeners.mjs
  '';
}
