# Checks of the favicon build (favicon/default.nix). The rules on the SVG are pure Nix, evaluated
# here: it is the drawing of parts.eye (the same viewBox, radius, path, circles and colours, in
# order), and the other copies of the mark carry the same shapes. The build runs xmllint on the SVG
# and `piabrota favicon-files-check` (scala/scripts/FaviconFiles.scala) on the ICO and the PNG,
# whose bytes Nix cannot read. `failures` is the list of the SVG checks that fail, for `nix eval`.
{ lib, callPackage, runCommand, libxml2, favicon }:
let
  svg = builtins.readFile ./favicon.svg;
  eye =
    let
      parts = builtins.readFile ../site/src/piabrota_site/parts.gleam;
      after = builtins.elemAt (builtins.split "\npub fn eye" parts) 2;
    in
    builtins.head (builtins.split "\n}" after);
  matches = re: s: map builtins.head (builtins.filter builtins.isList (builtins.split "(${re})" s));
  count = re: s: builtins.length (matches re s);
  # Every value of `attr`, in order: ` attr="v"` in the SVG, `a("attr", "v")` in the Gleam.
  inSvg = attr: map (m: builtins.head (builtins.match " ${attr}=\"([^\"]*)\"" m)) (matches " ${attr}=\"[^\"]*\"" svg);
  inGleam = attr: map (m: builtins.head (builtins.match "a\\(\"${attr}\", \"([^\"]*)\"\\)" m))
    (matches "a\\(\"${attr}\", \"[^\"]*\"\\)" eye);
  copies = [ ../figures-site/default.nix ../skills-site/src/www.gleam ];
  shapes = [ "d=.M12 50 Q50 18 88 50 Q50 82 12 50Z" "#BC2318" "#F7F3EA" "#2E9E4F" "#0B0D12" ];

  checks = {
    "favicon.svg has the SVG namespace" = count "xmlns=\"http://www.w3.org/2000/svg\"" svg == 1;
    "favicon.svg has no script, no link, no aria-hidden" = count "<script|href=|aria-hidden|onload|<image|<style|url\\(" svg == 0;
    "favicon.svg names no URL but its namespace" = matches "https?://[^\"]+" svg == [ "http://www.w3.org/2000/svg" ];
  }
  // lib.listToAttrs (map
    (attr: lib.nameValuePair "${attr} is the one of parts.eye" (inSvg attr == inGleam attr && inSvg attr != [ ]))
    [ "viewBox" "rx" "d" "fill" "cx" "cy" "r" ])
  // lib.listToAttrs (lib.concatMap
    (f: map (part: lib.nameValuePair "${baseNameOf f} has ${part}" (count part (builtins.readFile f) > 0)) shapes)
    copies);
  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
  filesCheck = (callPackage ../scala { }).command { name = "favicon-files-check"; };
in
runCommand "favicon-check" { nativeBuildInputs = [ libxml2 filesCheck ]; passthru = { inherit failures; }; } ''
  ${lib.concatMapStrings (f: "echo ${lib.escapeShellArg "FAIL ${f}"}\n") failures}
  echo "${toString (builtins.length (builtins.attrNames checks))} checks of the SVG, ${toString (builtins.length failures)} failed"
  xmllint --noout ${favicon}/favicon.svg
  favicon-files-check ${favicon}
  ${if failures == [ ] then "touch $out" else "exit 1"}
''
