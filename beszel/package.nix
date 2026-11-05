# Beszel (github.com/henrygd/beszel, MIT): the hub and the agent from ONE source, so the two always
# have the same version. A copy of nixpkgs' pkgs/by-name/be/beszel/package.nix (MIT, nixpkgs
# contributors) at a newer release than the nixpkgs of flake.lock has (0.18.7 there), with the
# pin values at the top. A copy and not `overrideAttrs`: the web UI (`webui`) is a second
# derivation that reads `finalAttrs.src`, and the test skips and the build tags change between
# releases, so an override would repeat most of the file. Nothing is in cache.nixos.org for this
# pin: the GitHub runner of deploy.yml builds it. docs/METRICS.md, "Updating the pin", says how to
# compute the three hashes. Bump all four values together.
{ buildGo127Module, lib, fetchFromGitHub, buildNpmPackage }:
let
  version = "0.21.1";
  # The source of the tag v${version}.
  hash = "sha256-OB1pbfUKeE+tu/ehhoJhkPBmOBDLiQzGxb74bin2Qmg=";
  # The Go modules (go.sum of the source).
  vendorHash = "sha256-NStpXYnaVkJxmzT1fIPFqSNbNSJqpnC0LsVQweFOwcI=";
  # The npm modules of the web UI (internal/site/package-lock.json).
  npmDepsHash = "sha256-pL4Qmi17CC4t6G/Mw/AgZUPf6cl0UPm75zfHVfrkoKI=";
in
buildGo127Module (finalAttrs: {
  pname = "beszel";
  inherit version vendorHash;

  src = fetchFromGitHub {
    owner = "henrygd";
    repo = "beszel";
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  webui = buildNpmPackage {
    inherit (finalAttrs) pname version src meta;
    inherit npmDepsHash;

    npmFlags = [ "--legacy-peer-deps" ];

    buildPhase = ''
      runHook preBuild

      npx lingui extract --overwrite
      npx lingui compile
      node --max_old_space_size=1024000 ./node_modules/vite/bin/vite.js build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r dist/* $out

      runHook postInstall
    '';

    sourceRoot = "${finalAttrs.src.name}/internal/site";
  };

  preBuild = ''
    mkdir -p internal/site/dist
    cp -r ${finalAttrs.webui}/* internal/site/dist
  '';

  # Tests that need a GPU tool, a block device or more than a few CPUs, as in nixpkgs.
  checkFlags =
    let
      skippedTests = [
        "TestCollectorStartHelpers/nvtop_collector"
        "TestCollectorStartHelpers/rocm-smi_collector"
        "TestIoctlDeviceSizeFailure"
        # This subtest assumes enough host CPUs for an 8s CPU delta over 1s to stay below 100%.
        "TestServiceUpdateCPUPercent/subsequent_call_calculates_CPU_percentage"
      ];
    in
    [
      "-skip=^${builtins.concatStringsSep "$|^" skippedTests}$"
      "-tags=testing,no_ui"
    ];

  postInstall = ''
    mv $out/bin/agent $out/bin/beszel-agent
    mv $out/bin/hub $out/bin/beszel-hub
  '';

  meta = {
    homepage = "https://github.com/henrygd/beszel";
    changelog = "https://github.com/henrygd/beszel/releases/tag/v${finalAttrs.version}";
    description = "Lightweight server monitoring hub with historical data, docker stats, and alerts";
    license = lib.licenses.mit;
  };
})
