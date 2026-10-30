# Mockups of the piabrota.art homepage, in pure Nix: three directions, each at desktop (1280 px)
# and phone (390 px) width. `files` maps each file name in docs/mockups/ to its text; `failures`
# lists the tests that failed (lib.runTests), empty when all pass. `just mockups` writes them.
{ lib, mu }:
let
  s = import ./svg.nix { inherit lib; };
  data = import ./data.nix;
  inherit (data) where;
  args = { inherit lib s data where; };
  directions = {
    fabric = import ./fabric.nix args;
    index = import ./index.nix args;
    paths = import ./paths.nix (args // { inherit mu; });
  };
  widths = { desktop = 1280; mobile = 390; };
  files = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList
    (name: draw: lib.mapAttrsToList
      (size: w: lib.nameValuePair "${name}-${size}.svg" (draw w))
      widths)
    directions));
  has = needle: hay: lib.hasInfix needle hay;
in
{
  inherit files;

  failures = lib.runTests {
    testSixFiles = {
      expr = builtins.attrNames files;
      expected = [ "fabric-desktop.svg" "fabric-mobile.svg" "index-desktop.svg" "index-mobile.svg" "paths-desktop.svg" "paths-mobile.svg" ];
    };
    # Every mockup names every project, and says where it meets the web.
    testEveryProjectInEveryMockup = {
      expr = lib.all
        (f: lib.all (p: has ">${p.name}" f) data.projects
          && lib.all (p: has (s.esc (p.path or (where p))) f) data.projects)
        (builtins.attrValues files);
      expected = true;
    };
    testWrapKeepsEveryWord = {
      expr = let t = "one proposition per sentence, read once"; in
        [ (s.wrap 12 t) (lib.concatStringsSep " " (s.wrap 12 t) == t) ];
      expected = [ [ "one" "proposition" "per" "sentence," "read once" ] true ];
    };
    testTextIsEscaped = {
      expr = s.text 1 2 { } "a < b & \"c\"";
      expected = ''<text x="1" y="2">a &lt; b &amp; &quot;c&quot;</text>'';
    };
    # The phone mockups are 390 px wide.
    testPhoneWidth = {
      expr = lib.all (n: has ''width="390"'' files.${n}) [ "fabric-mobile.svg" "index-mobile.svg" "paths-mobile.svg" ];
      expected = true;
    };
    testPathsKeepsTheDrawing = {
      expr = has "<title>无" files."paths-desktop.svg";
      expected = true;
    };
  };
}
