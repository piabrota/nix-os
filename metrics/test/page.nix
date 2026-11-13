# Checks of metrics/index.html and of the page's fixtures. The rules on the page are pure Nix,
# evaluated here; the derivation prints them. The fixtures are read by jq in the build, not by
# builtins.fromJSON: the hostile case has `Infinity`, which jq takes and Nix cannot parse. `nix build .#checks.x86_64-linux.metrics-page`
# (also in `just metrics-test`). `failures` is the list of the checks that fail, for `nix eval`.
{ lib, runCommand, jq }:
let
  page = builtins.readFile ../index.html;
  lines = lib.splitString "\n" page;
  # The parts of `s` that match the ERE `re`, in order.
  matches = re: s: map (m: builtins.head m) (builtins.filter builtins.isList (builtins.split "(${re})" s));
  count = re: s: builtins.length (matches re s);
  linesWith = re: builtins.filter (l: builtins.match ".*(${re}).*" l != null) lines;

  fixtures = ./fixtures;
  cases = builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir fixtures));
  jsonFiles = lib.concatMap
    (c: map (f: "${c}/data/${f}") (builtins.attrNames (builtins.readDir (fixtures + "/${c}/data"))))
    cases;

  # The page may name http://www.w3.org/2000/svg: it is an XML namespace, not a request.
  checks = {
    "page is under 20 KB" = builtins.stringLength page < 20480;
    "no URL to another host" = builtins.all (u: u == "http://www.w3.org/2000/svg") (matches "https?://[^\"' )]+" page);
    "no protocol-relative URL" = count "(src|href)=\"//" page == 0;
    "no innerHTML" = count "innerHTML" page == 0;
    "no outerHTML or insertAdjacentHTML" = count "outerHTML|insertAdjacentHTML" page == 0;
    "no eval" = count "(^|[^A-Za-z0-9_])eval\\(|new Function" page == 0;
    "no document.write" = count "document\\.write" page == 0;
    # The three icon links (favicon.nix) name a file of this host by an absolute path: nothing else may.
    "no external script, stylesheet or font" = count "<script[^>]+src=|<link[^>]+rel=\"stylesheet\"|@import|@font-face" page == 0;
    "every link is an icon of this host" = builtins.all
      (l: builtins.match ".*href=\"/(favicon\\.svg|favicon\\.ico|apple-touch-icon\\.png)\".*" l != null)
      (linesWith "<link[^>]+href=");
    "the three icon links" = builtins.length (linesWith "<link rel=\"(icon|apple-touch-icon)\"") == 3;
    "the policy lets the page load its own icon only" = count "img-src 'self'" page == 1;
    "no storage" = count "localStorage|sessionStorage|indexedDB|document\\.cookie" page == 0;
    "fetches only data/" = builtins.all (lib.hasPrefix "fetch(\"data/\"") (matches "fetch\\([^,)]*" page);
    "a policy forbids other requests" = count "connect-src 'self'" page == 1;
    "four fixture cases" = builtins.length cases == 4;
  };

  failures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) checks);
  total = builtins.length (builtins.attrNames checks) + builtins.length jsonFiles;
in
runCommand "metrics-page-check" { nativeBuildInputs = [ jq ]; passthru = { inherit failures; }; } ''
  failed=${toString (builtins.length failures)}
  ${lib.concatMapStrings (f: "echo ${lib.escapeShellArg "FAIL ${f}"}\n") failures}
  for f in ${lib.concatMapStringsSep " " lib.escapeShellArg jsonFiles}; do
    jq -e . "${fixtures}/$f" >/dev/null || { echo "FAIL fixture is JSON: $f"; failed=$((failed + 1)); }
  done
  echo "${toString total} checks, $failed failed"
  if [ "$failed" != 0 ]; then exit 1; fi
  touch $out
''
