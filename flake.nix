{
  description = "NixOS configuration of the piabrota Hostinger VPS, deployed from GitHub";

  inputs = {
    # stateVersion is 26.05, so follow the matching stable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, deploy-rs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      drawing = import ./drawings { inherit (nixpkgs) lib; };
      mockups = import ./mockups { inherit (nixpkgs) lib; mu = drawing.svg; };
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
      nixosConfigurations.piabrota = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };

      # deploy-rs: CI builds the closure, copies it over SSH and activates it. If the box
      # cannot be reached over SSH after activation, it rolls back by itself (magicRollback).
      deploy.nodes.piabrota = {
        # CI passes the real address with --hostname; this is only the default.
        hostname = "piabrota.art";
        sshUser = "deploy";
        user = "root";
        # The VPS pulls what cache.nixos.org has instead of the runner uploading it.
        fastConnection = false;
        remoteBuild = false;
        magicRollback = true;
        autoRollback = true;
        confirmTimeout = 60;
        profiles.system.path =
          deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.piabrota;
      };

      checks.${system} = deployPkgs.deploy-rs.lib.deployChecks self.deploy // {
        toplevel = self.nixosConfigurations.piabrota.config.system.build.toplevel;
        # The drawing's tests pass and the committed files are its output (`just drawing`).
        drawing = pkgs.runCommand "mu-art-check" { } ''
          ${pkgs.lib.concatMapStrings (f: "echo 'failed: ${f.name}' >&2\n") drawing.failures}
          ${pkgs.lib.optionalString (drawing.failures != [ ]) "exit 1"}
          art=${self.packages.${system}.mu-art}
          diff -u ${./docs/drawings/mu.svg} $art/mu.svg || { echo 'run `just drawing`' >&2; exit 1; }
          diff -u ${./docs/drawings/mu.desmos.json} $art/mu.desmos.json || { echo 'run `just drawing`' >&2; exit 1; }
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
          modules = [
            ./configuration.nix
            {
              piabrota.loco.apps.example = {
                package = pkgs.runCommand "example-loco" { } ''
                  mkdir -p $out/bin $out/share/example/config
                  printf '#!/bin/sh\nexit 0\n' > $out/bin/example-cli
                  chmod +x $out/bin/example-cli
                  touch $out/share/example/config/production.yaml
                '';
                domain = "example.piabrota.art";
                port = 5150;
                environmentFile = "/var/lib/loco-secrets/example.env";
              };
            }
          ];
        }).config.system.build.toplevel;
        # The system with KubeSolo on, so the module and the package build in CI before the
        # owner turns the flag on (docs/KUBESOLO.md). Never deployed.
        kubesolo-example = (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [ ./configuration.nix { piabrota.kubesolo.enable = true; } ];
        }).config.system.build.toplevel;
      };

      packages.${system} = {
        inherit (pkgs) deploy-rs;
        # The KubeSolo release binary (kubesolo/package.nix); not in nixpkgs.
        kubesolo = pkgs.callPackage ./kubesolo/package.nix { };
        # Mockups of the homepage, in pure Nix (mockups/): docs/mockups/*.svg.
        mockups = pkgs.linkFarm "mockups" (pkgs.lib.mapAttrsToList
          (name: text: { inherit name; path = pkgs.writeText name text; })
          mockups.files);
        # The site, prerendered from Gleam (site/): index.html and static/, with no runtime.
        site = pkgs.callPackage ./site { };
        # The site's facts as Gleam, from mockups/data.nix (`just site-data`; the build writes its own).
        site-data = pkgs.writeText "data.gleam"
          (import ./site/data.nix { inherit (pkgs) lib; data = import ./mockups/data.nix; });
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
