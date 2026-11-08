# The radio's live listeners count (piabrota/room's scripts/listeners.mjs): a small HTTP server
# with no dependency that sends the number of open /live/radio connections over server-sent
# events. It comes from the same pinned commit as the site (room-site/default.nix), so the page
# and its counter always match. It keeps nothing: no log, no address, no cookie.
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
