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
        drawing = self.packages.${system}.mu-art;
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
      };

      packages.${system} = {
        deploy-rs = pkgs.deploy-rs;
        # The README drawing; its tests check that docs/drawings/ is its output.
        mu-art = pkgs.rustPlatform.buildRustPackage {
          pname = "mu-art";
          version = "0.1.0";
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              ./drawings/Cargo.toml
              ./drawings/Cargo.lock
              ./drawings/src
              ./docs/drawings/mu.svg
              ./docs/drawings/mu.desmos.json
            ];
          };
          cargoRoot = "drawings";
          buildAndTestSubdir = "drawings";
          cargoLock.lockFile = ./drawings/Cargo.lock;
          meta.license = pkgs.lib.licenses.mpl20;
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.deploy-rs pkgs.just pkgs.shellcheck ];
      };

      formatter.${system} = pkgs.nixpkgs-fmt;
    };
}
