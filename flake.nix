{
  description = "NixOS configuration of the piabrota Hostinger VPSs, deployed from GitHub";

  inputs = {
    # stateVersion is 26.05, so follow the matching stable channel.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes Agent's package and NixOS module (hermes.nix). The input is pinned to a release tag,
    # so `nix flake update` never moves it to unreleased code. A bump changes the tag here, runs
    # `nix flake update hermes-agent` and changes hermesVersion in hermes.nix. It keeps its own
    # nixpkgs (unstable): its build patches tools, patchelf among them, for that version, and
    # the patches fail on nixos-26.05's (2026-11-02).
    hermes-agent.url = "github:NousResearch/hermes-agent/v0.23.0";
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
      # piabrota: KVM 1, the public web. piabrota2: KVM 4, the full Hermes and its dashboard.
      # One name for one VPS: the VPS name in hPanel = hosts/<name>/ = nixosConfigurations.<name>
      # = deploy.nodes.<name>. A new host is a directory in hosts/, a line here and one in the
      # address map of deploy.yml and freeze.yml.
      nixosConfigurations = {
        # The /hermes page on piabrota's site shows the Hermes that piabrota2 runs.
        piabrota = mkHost "piabrota" [{
          piabrota.site.hermes = self.nixosConfigurations.piabrota2.config.piabrota.site.hermes;
        }];
        piabrota2 = mkHost "piabrota2" [ ];
      };

      deploy.nodes =
        let
          nodes = {
            piabrota = mkNode "piabrota" "piabrota.art";
            # hermes.piabrota.art points at piabrota2 (docs/MIGRATION-KVM4.md); CI still passes its
            # address (the secret DEPLOY_HOST_KVM4).
            piabrota2 = mkNode "piabrota2" "hermes.piabrota.art";
          };
        in
        # `kvm4` is a temporary alias: .github/workflows/deploy.yml and freeze.yml still name the
          # node `kvm4`. Remove it in the pull request that renames the node in those workflows.
        nodes // { kvm4 = nodes.piabrota2; };

      checks.${system} = deployPkgs.deploy-rs.lib.deployChecks self.deploy // {
        toplevel = self.nixosConfigurations.piabrota.config.system.build.toplevel;
        toplevel-piabrota2 = self.nixosConfigurations.piabrota2.config.system.build.toplevel;
        # The favicon build: the three files exist, the ICO and the PNG are well formed, and the SVG
        # is the drawing of parts.eye (favicon/test.sh). The output has no store reference.
        favicon = pkgs.runCommand "favicon-check" { nativeBuildInputs = [ pkgs.libxml2 ]; } ''
          sh ${./favicon/test.sh} ${self.packages.${system}.favicon} ${pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [ ./site/src/piabrota_site/parts.gleam ./figures-site/default.nix ./skills-site/src/www.gleam ];
          }}
          touch $out
        '';
        # OpenRig's index.html still says `<link rel="icon" href="data:," />`, the literal that
        # openrig.nix swaps for the eye. If an upstream bump changes it, the swap does nothing.
        openrig-icon =
          let
            cfg = self.nixosConfigurations.piabrota2.config;
            literal = ''<link rel="icon" href="data:," />'';
          in
          pkgs.runCommand "openrig-icon-check" { } ''
            html=$(find -L ${cfg.piabrota.openrig.package} -path '*/ui/dist/index.html' | head -n 1)
            test -n "$html" || { echo "ui/dist/index.html is not in the OpenRig package: fix this check" >&2; exit 1; }
            grep -qF '${literal}' "$html" || { echo "the empty icon is not in $html: fix sub_filter in openrig.nix" >&2; grep -n 'icon' "$html" >&2; exit 1; }
            grep -qF -f ${pkgs.writeText "openrig-sub-filter" "sub_filter '${literal}'"} ${pkgs.writeText "openrig-web-root.conf" cfg.services.nginx.virtualHosts.${cfg.piabrota.openrig.web.domain}.locations."/".extraConfig} \
              || { echo "openrig.nix has no sub_filter for it" >&2; exit 1; }
            touch $out
          '';
        # The three icon locations of favicon.nix in a real nginx, in front of a proxy and behind
        # basic auth: right type, cache header and bytes; the proxied path still reaches its backend;
        # with no credentials the icons are as closed as the rest. No VM: it runs in the sandbox.
        favicon-nginx =
          let
            inherit (pkgs) lib;
            files = self.nixosConfigurations.piabrota.config.piabrota.favicon;
            locations = lib.concatStrings (lib.mapAttrsToList
              (name: l: "location ${name} { alias ${l.alias}; ${l.extraConfig} }\n")
              files.locations);
            conf = pkgs.writeText "favicon-nginx.conf" ''
              daemon off;
              pid nginx.pid;
              error_log error.log;
              events { }
              http {
                access_log off;
                client_body_temp_path tmp/body; proxy_temp_path tmp/proxy; fastcgi_temp_path tmp/fcgi; uwsgi_temp_path tmp/uwsgi; scgi_temp_path tmp/scgi;
                server {
                  listen 127.0.0.1:18080;
                  auth_basic "x";
                  auth_basic_user_file ${pkgs.writeText "htpasswd" "u:{PLAIN}p"};
                  ${locations}
                  location / { proxy_pass http://127.0.0.1:18081; }
                }
                server { listen 127.0.0.1:18081; location / { return 200 backend; } }
              }
            '';
          in
          pkgs.runCommand "favicon-nginx-check" { nativeBuildInputs = [ pkgs.nginx pkgs.curl ]; } ''
            mkdir tmp
            nginx -p "$PWD" -c ${conf} &
            for _ in $(seq 50); do curl -s -o /dev/null http://127.0.0.1:18080/ && break; sleep 0.1; done
            get() { curl -s -u u:p -D - -o "$2" "http://127.0.0.1:18080$1"; }
            check() { grep -qi "$2" "$1.h" || { echo "$1: no '$2'" >&2; cat "$1.h" >&2; exit 1; }; }
            get /favicon.svg svg > svg.h;      check svg 'content-type: image/svg+xml'
            get /favicon.ico ico > ico.h;      check ico 'content-type: image/x-icon'
            get /apple-touch-icon.png png > png.h; check png 'content-type: image/png'
            for f in svg ico png; do check $f 'cache-control: public, max-age=86400'; check $f '^HTTP/1.1 200'; done
            cmp svg ${files.files}/favicon.svg
            cmp ico ${files.files}/favicon.ico
            cmp png ${files.files}/apple-touch-icon.png
            test "$(curl -s -u u:p http://127.0.0.1:18080/some/page)" = backend
            test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/favicon.ico)" = 401
            test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/some/page)" = 401
            kill "$(cat nginx.pid)"
            touch $out
          '';
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
        # piabrota's page, and the backend still has the two routes that nginx refuses. If an
        # upstream bump renames one of them, the swap or the refusal does nothing and this fails.
        hermes-docs-url =
          let pkg = self.nixosConfigurations.piabrota2.config.services.hermes-agent.package;
          in pkgs.runCommand "hermes-docs-url-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
            web=$(jq -r '.env.HERMES_WEB_DIST' ${pkg}/command-map.json)
            grep -RqF --include='*.js' '`https://hermes-agent.nousresearch.com/docs/`' "$web" || {
              echo "the docs address is not in $web: fix sub_filter in hermes-web.nix" >&2
              find -L "$web" -maxdepth 2 >&2
              grep -RoE '.{0,60}hermes-agent\.nousresearch\.com/docs/?.{0,20}' "$web" >&2
              exit 1
            }
            py=$(jq -r '.env.HERMES_PYTHON' ${pkg}/command-map.json)
            routes=$(find -L "$(dirname "$(dirname "$py")")/lib" -type d -path '*/hermes_cli/web_routers' | head -n 1)
            test -n "$routes" || { echo "hermes_cli/web_routers is not in the package: fix this check" >&2; exit 1; }
            for p in /api/env/reveal /api/audio/voice-config; do
              grep -RqF "\"$p\"" "$routes" || { echo "the route $p is not in $routes: fix hermes-web.nix" >&2; exit 1; }
            done
            touch $out
          '';
        # site.nix's skills vhost and the redirect from /skills, read from the evaluated nginx
        # config of piabrota (nothing is built): the vhost has TLS, ACME, the icon and no-cache; www
        # redirects /skills and /skills/<page> and has no alias to the store; skillsDomain = null and
        # skills = null each remove the vhost and the redirect.
        site-skills =
          let
            inherit (pkgs) lib;
            inherit (self.nixosConfigurations) piabrota;
            siteCfg = piabrota.config.piabrota.site;
            vhosts = piabrota.config.services.nginx.virtualHosts;
            skills = vhosts.${siteCfg.skillsDomain};
            # The nginx vhosts of piabrota with one more module.
            variant = module: (piabrota.extendModules { modules = [ module ]; }).config.services.nginx.virtualHosts;
            # The locations of the www vhost that name /skills.
            skillsLocations = vh: lib.filterAttrs (n: _: lib.hasInfix "/skills" n) vh.${siteCfg.domain}.locations;
            removed = vh: !(vh ? ${siteCfg.skillsDomain}) && skillsLocations vh == { };
            tests = {
              vhostIsOnItsOwnName = siteCfg.skillsDomain == "skills.piabrota.art" && vhosts ? ${siteCfg.skillsDomain};
              vhostServesThePages = toString skills.root == toString siteCfg.skills;
              vhostIsHttpsOnly = skills.forceSSL && !skills.addSSL;
              vhostHasAcme = skills.enableACME;
              vhostHasTheIcon = lib.all (l: skills.locations ? ${l}) (lib.attrNames piabrota.config.piabrota.favicon.locations);
              vhostAsksForPagesAgain = lib.hasInfix "no-cache" skills.locations."/".extraConfig;
              wwwRedirectsSkills = vhosts.${siteCfg.domain}.locations."= /skills".return == "301 https://${siteCfg.skillsDomain}/";
              wwwRedirectsPages = lib.any (l: l.return == "301 https://${siteCfg.skillsDomain}/$rest$is_args$args")
                (lib.attrValues (skillsLocations vhosts));
              wwwHasNoAliasToSkills = lib.all (l: l.alias == null) (lib.attrValues (skillsLocations vhosts));
              noDomainNoVhostNoRedirect = removed (variant { piabrota.site.skillsDomain = null; });
              noPagesNoVhostNoRedirect = removed (variant { piabrota.site.skills = null; });
            };
            failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) tests);
          in
          pkgs.runCommand "site-skills-check" { } ''
            ${lib.concatMapStrings (n: "echo 'failed: ${n}' >&2\n") failed}
            ${lib.optionalString (failed != [ ]) "exit 1"}
            touch $out
          '';
        # site.nix's /llms.txt, read from the evaluated config of piabrota (nothing is built): the www
        # vhost answers it as UTF-8 text from the index of site/llms.nix, which names every service
        # and project of mockups/data.nix; llms = null removes the location.
        site-llms =
          let
            inherit (pkgs) lib;
            inherit (self.nixosConfigurations) piabrota;
            siteCfg = piabrota.config.piabrota.site;
            data = import ./mockups/data.nix;
            locations = vh: vh.${siteCfg.domain}.locations;
            llms = (locations piabrota.config.services.nginx.virtualHosts)."= /llms.txt";
            variant = module: (piabrota.extendModules { modules = [ module ]; }).config.services.nginx.virtualHosts;
            tests = {
              startsWithTheName = lib.hasPrefix "# piabrota\n\n> " siteCfg.llms;
              namesEveryService = lib.all (s: lib.hasInfix "(https://${s.host}/)" siteCfg.llms) data.services;
              namesEveryProject = lib.all (p: lib.hasInfix "- [${p.name}](" siteCfg.llms) data.projects;
              namesEveryFork = lib.all (f: lib.hasInfix "[${f.parent}](" siteCfg.llms) data.forks;
              hasNoRelativeLink = !(lib.hasInfix "](/" siteCfg.llms);
              servesTheText = lib.hasSuffix "-llms.txt" (toString llms.alias);
              isUtf8Text = lib.hasInfix "charset utf-8;" llms.extraConfig && lib.hasInfix "text/plain" llms.extraConfig;
              nullRemovesIt = !((locations (variant { piabrota.site.llms = null; })) ? "= /llms.txt");
            };
            failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) tests);
          in
          pkgs.runCommand "site-llms-check" { } ''
            ${lib.concatMapStrings (n: "echo 'failed: ${n}' >&2\n") failed}
            ${lib.optionalString (failed != [ ]) "exit 1"}
            touch $out
          '';
        # The root llms.txt, the index of all the work of h0ffmann (README.md links it): it has the
        # llmstxt.org shape, links the site's index of piabrota, and carries no DOI (the owner, 2026-11-11).
        repo-llms =
          let
            inherit (pkgs) lib;
            text = builtins.readFile ./llms.txt;
            tests = {
              startsWithTheName = lib.hasPrefix "# Matheus Hoffmann (h0ffmann)\n\n> " text;
              linksTheSiteIndex = lib.hasInfix "https://www.piabrota.art/llms.txt" text;
              hasNoDoi = !(lib.hasInfix "doi.org" text) && !(lib.hasInfix "10.5281" text);
              hasNoRelativeLink = !(lib.hasInfix "](/" text);
              readmeLinksIt = lib.hasInfix "(llms.txt)" (builtins.readFile ./README.md);
            };
            failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) tests);
          in
          pkgs.runCommand "repo-llms-check" { } ''
            ${lib.concatMapStrings (n: "echo 'failed: ${n}' >&2\n") failed}
            ${lib.optionalString (failed != [ ]) "exit 1"}
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
        # Every nginx virtual host under piabrota.art is a site of design/sites.nix or is listed there as
        # hidden, and every site names a host that a system serves. Evaluation only: no system is built.
        design-sites =
          let
            inherit (pkgs) lib;
            list = import ./design/sites.nix;
            served = lib.unique (lib.concatMap
              (name: lib.attrNames self.nixosConfigurations.${name}.config.services.nginx.virtualHosts)
              (lib.attrNames self.nixosConfigurations));
            underPiabrota = lib.filter (h: h == "piabrota.art" || lib.hasSuffix ".piabrota.art" h) served;
            listed = map (s: s.host) list.sites ++ list.hidden;
            unlisted = lib.filter (h: !(lib.elem h listed)) underPiabrota;
            unserved = lib.filter (s: !(lib.elem s.host served)) list.sites;
          in
          pkgs.runCommand "design-sites-check" { } ''
            ${lib.concatMapStrings (h: "echo 'not in design/sites.nix: ${h}' >&2\n") unlisted}
            ${lib.concatMapStrings (s: "echo 'no system serves ${s.id}: ${s.host}' >&2\n") unserved}
            ${lib.optionalString (unlisted != [ ] || unserved != [ ]) "exit 1"}
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
              # As in nixosConfigurations.piabrota: without piabrota2's facts the site's /hermes test fails.
              piabrota.site.hermes = self.nixosConfigurations.piabrota2.config.piabrota.site.hermes;
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
        # metrics.nix in four VMs: the collector, the public page, robots.txt and the agent block,
        # the optional login, the pull and the published location (metrics/test.nix). Needs KVM to
        # run in reasonable time.
        metrics = pkgs.testers.runNixOSTest ./metrics/test.nix;
      };

      packages.${system} = {
        inherit (pkgs) deploy-rs;
        # The PGX release, patched for the store (pgx/package.nix); not in nixpkgs.
        pgx = pkgs.callPackage ./pgx/package.nix { };
        # The eye as favicon.svg, favicon.ico and apple-touch-icon.png (favicon/): served on every vhost.
        favicon = pkgs.callPackage ./favicon { };
        # Mockups of the homepage, in pure Nix (mockups/): docs/mockups/*.svg.
        mockups = pkgs.linkFarm "mockups" (pkgs.lib.mapAttrsToList
          (name: text: { inherit name; path = pkgs.writeText name text; })
          mockups.files);
        # The site, prerendered from Gleam (site/): the pages and static/, with no runtime. The
        # system's own, so /hermes shows the Hermes that hermes.nix configures.
        site = self.nixosConfigurations.piabrota.config.piabrota.site.root;
        # The skills website (skills-site/), prerendered from Gleam: served at skills.piabrota.art.
        skills-site = self.nixosConfigurations.piabrota.config.piabrota.site.skills;
        # The website of h0ffmann/ww3-gpu (ww3-site/), prerendered from Gleam: served at ww3.piabrota.art.
        ww3-site = self.nixosConfigurations.piabrota2.config.piabrota.ww3.root;
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
