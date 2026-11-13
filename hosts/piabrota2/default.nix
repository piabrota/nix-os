# piabrota2: the Hostinger KVM 4 VPS (4 vCPU and 16 GB RAM by Hostinger's plan list; `just remote-specs`
# gives the real figures), the second host. It runs Hermes: the full Hermes (upstream's `full`
# package and upstream's defaults), its GitHub App, its web dashboard on hermes.piabrota.art, PGX
# and OpenRig, which Hermes operates. It does not serve www.piabrota.art: that name points at
# piabrota.
#
# Its setup from an empty VPS is docs/DEPLOY.md, "A second host"; the move of Hermes from piabrota
# is docs/MIGRATION-KVM4.md. Nothing is cloned or built on the VPS.
{ ... }:
{
  imports = [
    ../../configuration.nix
    ../../hermes.nix
    ../../hermes-github.nix
    # The dashboard behind nginx, TLS and basic auth. hermes.piabrota.art must point at this box.
    ../../hermes-web.nix
    # OpenRig (openrig.nix): loopback only, no DNS, no port.
    ../../openrig.nix
    # The room (piabrota/room) on room.piabrota.art, which must point at this box.
    ../../room.nix
    # The HTML pages of h0ffmann/proof on proof.piabrota.art and those of piabrota/pirsig on
    # pirsig.piabrota.art; both names must point at this box.
    ../../proof.nix
    # The website of h0ffmann/ww3-gpu on wave.piabrota.art, which must point at this box.
    ../../ww3.nix
    # The website of h0ffmann/closed-source on closed.piabrota.art, which must point at this box.
    ../../closed.nix
    # The website of h0ffmann/h0ffmann (the owner's profile) on hffmnn.piabrota.art, which must point at
    # this box.
    ../../hffmnn.nix
    # marola-site (marola-dev/marola-site): the Haskell server behind nginx (docs/MAROLA-SITE.md).
    ../../marola-site.nix
    # tyler-durden-bot (tyler-durden-bot.nix): a Hermes webhook route that summarizes large pull
    # requests on h0ffmann/proof. tyler.piabrota.art must point at this box before it is on.
    ../../tyler-durden-bot.nix
  ];

  # piabrota2 is the VPS name in hPanel; Hostinger first named it srv2125808 (srv2125808.hstgr.cloud
  # stays its address). Without this line NixOS writes `nixos` to /etc/hostname; see
  # hosts/piabrota/default.nix.
  networking.hostName = "piabrota2";

  # Far above what Hermes used on piabrota (1G and CPUWeight 50), so a runaway task cannot starve
  # sshd and make a deploy roll back: half the RAM, and half the CPU share of other units when the
  # four cores are busy. The dashboard has its own 2G (hermes-web.nix).
  systemd.services.hermes-agent.serviceConfig = {
    MemoryMax = "8G";
    CPUWeight = 50;
  };

  piabrota.hermesWeb.enable = true;
  piabrota.pgx.enable = true;
  # The lofi bot (lofi.nix, docs/LOFI.md). Idle until its token and IDs are on the box.
  piabrota.lofi.enable = true;
  # Hermes operates it with `rig` and the skill hermes-rig; docs/OPENRIG.md.
  piabrota.openrig.enable = true;
  # The web UI at rig.piabrota.art, behind the dashboard's login (docs/OPENRIG.md, "The web UI").
  piabrota.openrig.web.enable = true;
  piabrota.openrig.web.domain = "rig.piabrota.art";
  # The rigs wave-forecaster-dev and wave-forecaster-dev-integrate: the seats' Rust tools, their
  # folders, the outbox and a read-only token for h0ffmann/chaceon (docs/OPENRIG.md). On since
  # 2026-11-07, when the owner asked for the port rig to run 24/7: the keeper openrig-wf-keeper
  # restores it when it stops. The integrate rig stays manual.
  piabrota.openrig.waveForecaster.enable = true;
  piabrota.openrig.waveForecaster.alwaysOn.enable = true;
  # marola-front and marola-back on the rig piabrota-dev: two builders in parallel, read tokens of
  # marola-pr-bot, and Hermes pushes and opens these pull requests as marola-pr-bot (docs/OPENRIG.md).
  # Without the App's key file on the box (marola-bot.nix) it mints nothing and the seats clone no
  # private repository.
  piabrota.openrig.marola.enable = true;
  # Setup B of the same two repositories on Claude Code (rig piabrota-dev-claude), to compare with omp.
  piabrota.openrig.marola.claude.enable = true;
  # Three seats of one rig at a time: `builder` on marola-back and `front-builder` on marola-front
  # build in parallel, and share the reviewer (docs/OPENRIG.md, "Limits"). The MemoryMax values of
  # the box then sum to 14.25 GiB of 15.6 GiB; a cap is a ceiling, not a use.
  piabrota.openrig.memoryMax = "4G";
  piabrota.openrig.memoryHigh = "3G";
  # The 3D room, piabrota/room at a pinned commit (room-site/default.nix), at room.piabrota.art.
  piabrota.room.enable = true;
  # The same room on grid.piabrota.art, opened on its ▲ grid view (room.nix). The name must point
  # at this box.
  piabrota.room.grid.enable = true;
  # The HTML pages of h0ffmann/proof and of piabrota/pirsig at pinned commits, each with an index
  # (proof-site/), at proof.piabrota.art and pirsig.piabrota.art.
  piabrota.proof.enable = true;
  # The website of h0ffmann/ww3-gpu at a pinned commit (ww3-site/), at wave.piabrota.art.
  piabrota.ww3.enable = true;
  # The website of h0ffmann/closed-source at a pinned commit (closed-site/), at closed.piabrota.art.
  piabrota.closedSource.enable = true;
  # The website of h0ffmann/h0ffmann at a pinned commit (hffmnn-site/), at hffmnn.piabrota.art.
  # Off until hffmnn.piabrota.art has its A record at this box: without it the ACME order fails at
  # activation and deploy-rs rolls every piabrota2 deploy back (deploys of #241, #242, #243).
  piabrota.hffmnn.enable = false;
  # marola-site at a pinned commit (marola-site/default.nix). Step 1 of docs/MAROLA-SITE.md: on
  # marola.piabrota.art, whose A record must point at this box first, while marola.dev stays on the
  # Cloudflare Worker. Step 2 sets domain = "marola.dev" and redirects = [ "www.marola.dev"
  # "marola.piabrota.art" ] after Cloudflare points those names here.
  piabrota.marolaSite = {
    enable = true;
    domain = "marola.piabrota.art";
    # The boards are built here four times a day (marola-site.nix, docs/MAROLA-SITE.md). The
    # token file /etc/marola/ghcr-token must be on the box, or each build fails at the pull.
    boards.build.enable = true;
    # marola-site's marola-image (jvm-0c1e050) is gone from ghcr: "manifest unknown". This is
    # marola-app main's jvm-7061a08 (CI run 39499882444), with the same --site and board schema.
    # Drop it when marola-site's pin names an image that exists.
    boards.build.image = "ghcr.io/marola-dev/marola-app:jvm-7061a08@sha256:7656c11b9e429059913310f5e934a6dd82028d33974cffdb3c5ee2c5e2a7d286";
    # marola-site's site.yml, moved here from GitHub Actions: after each board build, the legacy page
    # and these boards go to the Cloudflare Worker that serves marola.dev. Needs
    # /etc/marola/cloudflare.env and /etc/marola/mapbox-token (docs/MAROLA-SITE.md). Off after step 2,
    # when marola.dev is this box.
    worker.enable = true;
  };
  # tyler-durden-bot, off until the owner has made the App, written /var/lib/tyler-durden-secrets/app.env
  # and WEBHOOK_SECRET in hermes.env, and pointed tyler.piabrota.art here (docs/TYLER-DURDEN.md).
  piabrota.tylerDurden.enable = false;
  # Live metrics (metrics.nix, docs/METRICS.md): the page at metrics.piabrota.art, which must point at
  # this box, this host's own collector, and the pull of piabrota's file.
  piabrota.metrics = {
    name = "piabrota2";
    label = "piabrota2 (KVM 4)";
    collector.enable = true;
    # Up or down for each site of this host, and the commit count of piabrota/nix-os.
    probe.enable = true;
    # The visits of each site in the last 24 h, from a log of the pages browsers got (docs/METRICS.md, "Visits").
    visits.enable = true;
    web.enable = true;
    pull = {
      enable = true;
      url = "https://www.piabrota.art/_metrics/piabrota.json";
    };
  };
}
