{
  description = "NixOS configuration of the piabrota Hostinger VPSs, deployed from GitHub";

  inputs = {
    # stateVersion is 26.05, so follow the matching stable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes Agent's package and NixOS module (hermes.nix). Its main branch is what it publishes;
    # the lock pins a commit, and the weekly flake update moves it in a PR that CI builds. It keeps
    # its own nixpkgs (unstable): its build patches tools, patchelf among them, for that version, and
    # the patches fail on nixos-26.05's (2026-11-02).
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = { self, nixpkgs, deploy-rs, hermes-agent }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      drawing = import ./drawings { inherit (nixpkgs) lib; };
      mockups = import ./mockups { inherit (nixpkgs) lib; mu = drawing.svg; };
      # One system per directory of hosts/ (docs/DEPLOY.md, "A second host"): configuration.nix
      # plus what is the host's own.
      mkHost = name: extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit hermes-agent; };
        modules = [ ./hosts/${name} ] ++ extraModules;
      };
      # deploy-rs: CI builds the closure, copies it over SSH and activates it. If the box
      # cannot be reached over SSH after activation, it rolls back by itself (magicRollback).
      # CI passes the real address with --hostname (a secret per host); `hostname` is only the
      # default.
      mkNode = name: hostname: {
        inherit hostname;
        sshUser = "deploy";
        user = "root";
        # The VPS pulls what cache.nixos.org has instead of the runner uploading it.
        fastConnection = false;
        remoteBuild = false;
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 60;
        profiles.system.path =
          deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.${name};
      };
      # deploy-rs's lib with nixpkgs' deploy-rs binary, which cache.nixos.org has, so CI does
      # not compile it (the overlay the deploy-rs README gives for this).
      deployPkgs = import nixpkgs {
        inherit system;
        overlays = [
          deploy-rs.overlays.default
          (_: super: { deploy-rs = { inherit (pkgs) deploy-rs; inherit (super.deploy-rs) lib; }; })
        ];
      };
    in
    {
      # piabrota: KVM 1, the public web. kvm4: KVM 4, the full Hermes and its dashboard.
      # A new host is a directory in hosts/, a line here and one in deploy.yml's matrix.
      nixosConfigurations = {
        # The /hermes page on piabrota's site shows the Hermes that kvm4 runs.
        piabrota = mkHost "piabrota" [{
          piabrota.site.hermes = self.nixosConfigurations.kvm4.config.piabrota.site.hermes;
        }];
        kvm4 = mkHost "kvm4" [ ];
      };

      deploy.nodes = {
        piabrota = mkNode "piabrota" "piabrota.art";
        # hermes.piabrota.art points at kvm4 (docs/MIGRATION-KVM4.md); CI still passes its address
        # (the secret DEPLOY_HOST_KVM4).
        kvm4 = mkNode "kvm4" "hermes.piabrota.art";
      };

      checks.${system} = deployPkgs.deploy-rs.lib.deployChecks self.deploy // {
        toplevel = self.nixosConfigurations.piabrota.config.system.build.toplevel;
        toplevel-kvm4 = self.nixosConfigurations.kvm4.config.system.build.toplevel;
        # The drawing's tests pass and the committed files are its output (`just drawing`).
        drawing = pkgs.runCommand "mu-art-check" { } ''
          ${pkgs.lib.concatMapStrings (f: "echo 'failed: ${f.name}' >&2\n") drawing.failures}
          ${pkgs.lib.optionalString (drawing.failures != [ ]) "exit 1"}
          art=${self.packages.${system}.mu-art}
          diff -u ${./docs/drawings/mu.svg} $art/mu.svg || { echo 'run `just drawing`' >&2; exit 1; }
          diff -u ${./docs/drawings/mu.desmos.json} $art/mu.desmos.json || { echo 'run `just drawing`' >&2; exit 1; }
          touch $out
        '';
        # The unit tests of the owner's Hermes plugins (hermes/plugins/), with git and a stub gh.
        hermes-plugins = pkgs.runCommand "hermes-plugins-test"
          { nativeBuildInputs = [ pkgs.python3 pkgs.git ]; } ''
          export HOME=$TMPDIR PYTHONDONTWRITEBYTECODE=1
          cd ${./hermes/plugins}/tests && python3 -m unittest -v test_plugins
          touch $out
        '';
        # The dashboard bundle still holds the docs address that hermes-web.nix swaps for
        # piabrota's page. If an upstream bump renames it, the swap does nothing and this fails.
        hermes-docs-url =
          let pkg = self.nixosConfigurations.kvm4.config.services.hermes-agent.package;
          in pkgs.runCommand "hermes-docs-url-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
            web=$(jq -r '.env.HERMES_WEB_DIST' ${pkg}/command-map.json)
            grep -rqF --include='*.js' '"https://hermes-agent.nousresearch.com/docs/"' "$web" \
              || { echo "the docs address is not in $web: fix sub_filter in hermes-web.nix" >&2; exit 1; }
            touch $out
          '';
        # The mockups' tests pass and the committed files are their output (`just mockups`).
        mockups = pkgs.runCommand "mockups-check" { } ''
          ${pkgs.lib.concatMapStrings (f: "echo 'failed: ${f.name}' >&2\n") mockups.failures}
          ${pkgs.lib.optionalString (mockups.failures != [ ]) "exit 1"}
          ${pkgs.lib.concatMapStrings (n: ''
            diff -u ${./docs/mockups + "/${n}"} ${self.packages.${system}.mockups}/${n} || { echo 'run `just mockups`' >&2; exit 1; }
            diff -u ${./wiki/mockups + "/${n}"} ${self.packages.${system}.mockups}/${n} || { echo 'run `just mockups`' >&2; exit 1; }
          '') (builtins.attrNames mockups.files)}
          touch $out
        '';
        # The system with one stand-in Loco app, so the module and the hosting stack (nginx,
        # ACME, the backup timer) build in CI before a real app needs them. Never deployed.
        loco-example = (nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit hermes-agent; };
          modules = [
            ./hosts/piabrota
            {
              piabrota.loco.apps.example = {
                package = pkgs.runCommand "example-loco" { } ''
                  mkdir -p $out/bin $out/share/example/config
                  printf '#!/bin/sh\nexit 0\n' > $out/bin/example-cli
                  chmod +x $out/bin/example-cli
                  touch $out/share/example/config/production.yaml
                '';
                domain = "example.piabrota.art";
                port = 5151; # 5150 is the notes demo (apps.nix)
                environmentFile = "/var/lib/loco-secrets/example.env";
              };
            }
          ];
        }).config.system.build.toplevel;
        # pgx.nix in a VM: the unit starts in its sandbox, takes a password and keeps its data
        # across a restart (pgx/test.nix).
        pgx = pkgs.testers.runNixOSTest ./pgx/test.nix;
      };

      packages.${system} = {
        inherit (pkgs) deploy-rs;
        # The PGX release, patched for the store (pgx/package.nix); not in nixpkgs.
        pgx = pkgs.callPackage ./pgx/package.nix { };
        # Mockups of the homepage, in pure Nix (mockups/): docs/mockups/*.svg.
        mockups = pkgs.linkFarm "mockups" (pkgs.lib.mapAttrsToList
          (name: text: { inherit name; path = pkgs.writeText name text; })
          mockups.files);
        # The site, prerendered from Gleam (site/): the pages and static/, with no runtime. The
        # system's own, so /hermes shows the Hermes that hermes.nix configures.
        site = self.nixosConfigurations.piabrota.config.piabrota.site.root;
        # The site's facts as Gleam, from mockups/data.nix (`just site-data`; the build writes its own).
        site-data = pkgs.writeText "data.gleam"
          (import ./site/data.nix {
            inherit (pkgs) lib;
            data = import ./mockups/data.nix;
            inherit (self.nixosConfigurations.piabrota.config.piabrota.site) hermes;
          });
        # The README drawing, in pure Nix (drawings/): mu.svg, mu.desmos.json and mu-check.svg.
        mu-art = pkgs.linkFarm "mu-art" [
          { name = "mu.svg"; path = pkgs.writeText "mu.svg" drawing.svg; }
          { name = "mu.desmos.json"; path = pkgs.writeText "mu.desmos.json" drawing.desmos; }
          { name = "mu-check.svg"; path = pkgs.writeText "mu-check.svg" drawing.checkSvg; }
        ];
      };

      devShells.${system} = {
        default = pkgs.mkShell {
          packages = [ pkgs.deploy-rs pkgs.just pkgs.shellcheck ];
        };
        # Work on site/ (`just site`, `just site-serve`): gleam and node for the build, and node's
        # npx for the OpenPencil MCP server (.mcp.json). Never on the VPS.
        site = pkgs.mkShell {
          packages = [ pkgs.gleam pkgs.nodejs pkgs.just ];
        };
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
