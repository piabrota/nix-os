# The eye as the icon of every site under piabrota.art. Every nginx vhost of this repository
# carries `config.piabrota.favicon.locations` in its `locations`, so the three files answer on
# every name, in front of any proxy:
#   locations = config.piabrota.favicon.locations // { ... };
# A new vhost gets the icon by adding that one term. The files are favicon/ (favicon/default.nix);
# the pages that we write link them (docs/SITE.md, "The icon"). An app that we do not write names
# its own icon: hermes-web.nix, openrig.nix and room.nix answer for that name too.
# An add_header in a location drops the server's, and NixOS's nginx check (gixy) fails the build
# when a location does that. The dashboards set four headers on the server; the icon locations
# repeat those four, the same on every vhost (HSTS is ignored over plain HTTP).
{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
  files = pkgs.callPackage ./favicon { };
  file = name: type: {
    "= /${name}" = {
      alias = "${files}/${name}";
      extraConfig = ''
        default_type ${type};
        add_header Cache-Control "public, max-age=86400" always;
        add_header X-Frame-Options DENY always;
        add_header Referrer-Policy no-referrer always;
        add_header X-Content-Type-Options nosniff always;
        add_header Strict-Transport-Security "max-age=31536000" always;
      '';
    };
  };
in
{
  options.piabrota.favicon = {
    files = mkOption {
      type = types.package;
      readOnly = true;
      default = files;
      description = "favicon.svg, favicon.ico and apple-touch-icon.png, built on the builder (favicon/default.nix).";
    };
    locations = mkOption {
      type = types.attrsOf types.attrs;
      readOnly = true;
      internal = true;
      default =
        file "favicon.svg" "image/svg+xml"
        // file "favicon.ico" "image/x-icon"
        // file "apple-touch-icon.png" "image/png";
      description = "The three exact locations that serve the icon. Add them to the `locations` of every vhost.";
    };
    links = mkOption {
      type = types.str;
      readOnly = true;
      default = import ./favicon/links.nix;
      description = "The three <link> tags that name the icon, for a page that sub_filter rewrites (openrig.nix).";
    };
  };
}
