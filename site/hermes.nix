# The /hermes page's facts: Hermes's configuration as plain YAML, read from the evaluated NixOS
# options (services.hermes-agent in hermes.nix), so the page changes when hermes.nix changes.
# Nothing secret reaches it: the env files are not read or named, and any key that names a token,
# a key, a secret, a password or allowed users is dropped. Store paths keep their name and lose
# their hash, because the site's output must name no store path (allowedReferences = [ ]).
{ lib, cfg, unit, lock }:
let
  inherit (builtins) isAttrs isList isString isBool isInt isFloat isNull toJSON;

  secret = k: builtins.match ".*(token|key|secret|passw|allowed|users|auth|credential).*" (lib.toLower k) != null;
  clean = v:
    if isAttrs v then lib.mapAttrs (_: clean) (lib.filterAttrs (k: _: !secret k) v)
    else if isList v then map clean v
    else v;

  # /nix/store/<hash>-name → /nix/store/…-name, and no string context.
  unstore = s:
    lib.concatMapStrings (x: if isList x then "/nix/store/…-" else x)
      (builtins.split "/nix/store/[0-9a-z]{32}-" (builtins.unsafeDiscardStringContext s));

  # Unquoted when YAML reads it back as the same string: no number or date, no keyword, no ": ".
  plain = s:
    builtins.match "[A-Za-z0-9_/][A-Za-z0-9_./:@+ -]*[A-Za-z0-9_./@+-]|[A-Za-z_/]" s != null
    && builtins.match "[0-9][0-9.:+ -]*|.*: .*| .*|.* #.*" s == null
    && !(lib.elem (lib.toLower s) [ "true" "false" "null" "yes" "no" "on" "off" "y" "n" "~" ]);
  scalar = v:
    if isString v then (let s = unstore v; in if plain s then s else toJSON s)
    else if isBool v then lib.boolToString v
    else if isInt v || isFloat v then toString v
    else if isNull v then "null"
    else toJSON (lib.mapAttrsRecursive (_: x: if isString x then unstore x else x) v);
  key = k: if builtins.match "[A-Za-z0-9_.-]+" k != null then k else toJSON k;
  leaf = v: !(isAttrs v || isList v) || v == { } || v == [ ];
  flat = v: if v == { } then "{}" else if v == [ ] then "[]" else scalar v;

  # Block YAML: maps and lists nest by two spaces; a map or list inside a list is written in flow
  # style (JSON is YAML), which this configuration never has.
  yaml = ind: v:
    if isAttrs v then
      lib.concatMapStrings
        (k:
          let x = v.${k}; in
          if leaf x then "${ind}${key k}: ${flat x}\n"
          else "${ind}${key k}:\n" + yaml "${ind}  " x)
        (lib.attrNames v)
    else lib.concatMapStrings (x: "${ind}- ${if leaf x then flat x else scalar x}\n") v;

  name = p: p.pname or (lib.getName p);
  # The flake builds Hermes as 0.0.0: its commit, in `upstream`, is the version.
  version = p: if (p.version or "0.0.0") == "0.0.0" then "" else " ${p.version}";
  short = builtins.substring 0 7 lock.rev;
  # Seconds since 1970 to YYYY-MM-DD (Hinnant's civil_from_days), for the lock's lastModified.
  date = secs:
    let
      z = secs / 86400 + 719468;
      era = z / 146097;
      doe = z - era * 146097;
      yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      mp = (5 * doy + 2) / 153;
      d = doy - (153 * mp + 2) / 5 + 1;
      m = if mp < 10 then mp + 3 else mp - 9;
      y = yoe + era * 400 + (if m <= 2 then 1 else 0);
      two = n: if n < 10 then "0${toString n}" else toString n;
    in
    "${toString y}-${two m}-${two d}";

  # What Hermes reads: the module writes these settings to config.yaml, with terminal.cwd set to
  # the working directory first (its nixosModules.nix, "The rendered config.yaml").
  config = clean (lib.recursiveUpdate { terminal.cwd = cfg.workingDirectory; } cfg.settings);

  # How nix-os runs it: the unit and what the module installs around config.yaml.
  service = clean {
    unit = "hermes-agent.service";
    upstream = {
      repository = "github.com/NousResearch/hermes-agent";
      commit = lock.rev;
      date = date lock.lastModified;
    };
    package = "${name cfg.package}${version cfg.package}";
    extras = cfg.extraDependencyGroups;
    state = cfg.stateDir;
    working_directory = cfg.workingDirectory;
    # systemd's defaults when the host sets no limit (kvm4).
    memory_max = unit.MemoryMax or "infinity";
    cpu_weight = unit.CPUWeight or 100;
    plugins = map name cfg.extraPlugins;
    packages = map (p: "${name p}${version p}") cfg.extraPackages;
    files = lib.attrNames cfg.hermesHomeFiles ++ lib.attrNames cfg.documents;
    inherit (cfg) environment;
  };
  text = {
    config = yaml "" config;
    service = yaml "" service;
  };
in
# A last guard: if a secret's name slipped into the text, the build stops here.
assert lib.all
  (t: !lib.any (w: lib.hasInfix w t) [ "hermes.env" "OAUTH" "ALLOWED_USERS" "PRIVATE KEY" ]
    || throw "site/hermes.nix: the /hermes page would name a secret")
  (lib.attrValues text);
text // {
  facts = [
    { label = "unit"; value = service.unit; }
    { label = "model"; value = cfg.settings.model.default or ""; }
    { label = "subagents"; value = cfg.settings.delegation.model or ""; }
    { label = "memory"; value = "${toString service.memory_max} max"; }
    { label = "upstream"; value = "${short} · ${service.upstream.date}"; }
  ];
  upstream = "https://github.com/NousResearch/hermes-agent/commit/${lock.rev}";
}
