# Live metrics, home-made (docs/METRICS.md): processes, memory and vCPU of each host on one page at
# metrics.piabrota.art. No daemon stays resident:
#   collector  a timer runs metrics/collect.sh every 10 s; it writes /run/metrics-web/<name>.json
#   web        nginx serves metrics/index.html and /data/ from that folder, public by default, with a
#              robots.txt and a block of named AI agents (a login file is optional)
#   publish    (KVM 1) one location on the www vhost serves the host's file to one address
#   pull       (KVM 4) a timer fetches that file and keeps it beside its own
# Everything is off by default. The web name must point at its host before `web.enable` is on, or the
# ACME order fails on the deploy and deploy-rs rolls the switch back (docs/SITE.md).
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkMerge mkOption types;
  cfg = config.piabrota.metrics;
  anyOn = cfg.collector.enable || cfg.web.enable || cfg.publish.enable || cfg.pull.enable;
  outDir = "/run/metrics-web";
  stateDir = "/run/metrics-state";

  # The scripts get their shebang patched to a store shell; the tools they call are on the unit's PATH.
  script = name: file: pkgs.runCommand name { } ''
    install -D -m 0755 ${file} $out/bin/${name}
    patchShebangs $out/bin/${name}
  '';
  collect = script "metrics-collect" ./metrics/collect.sh;
  pull = script "metrics-pull" ./metrics/pull.sh;
  # What this generation runs, counted once at build time (docs/METRICS.md, "The inventory"). The
  # names come from the evaluated config; a module that this host does not import counts 0. The
  # skills are the SKILL.md files in Hermes's skill folders and plugins, so they need a build.
  hermes = config.services.hermes-agent or { };
  hermesOn = hermes.enable or false;
  rigSpecs = config.environment.etc."openrig/specs".source or null;
  dirsIn = path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
  counts = {
    apps = lib.length (lib.attrNames config.piabrota.loco.apps);
    sites = lib.length (lib.attrNames (lib.filterAttrs (name: vhost: name != "_" && vhost.globalRedirect == null)
      (lib.optionalAttrs config.services.nginx.enable config.services.nginx.virtualHosts)));
    rigs = if (config.piabrota.openrig.enable or false) && rigSpecs != null then lib.length (dirsIn (rigSpecs + "/rigs")) else 0;
    agents =
      if (config.piabrota.openrig.enable or false) && rigSpecs != null
      then lib.length (lib.filter (n: !(lib.hasSuffix "shared" n)) (dirsIn (rigSpecs + "/agents"))) else 0;
    plugins = if hermesOn then lib.length hermes.settings.plugins.enabled else 0;
    mcp = if hermesOn then lib.length (lib.attrNames hermes.mcpServers) else 0;
    packages = lib.length config.environment.systemPackages;
    timers = lib.length (lib.attrNames (lib.filterAttrs (_: timer: timer.enable) config.systemd.timers));
  };
  skillDirs = lib.optionals hermesOn (map toString (hermes.settings.skills.external_dirs ++ hermes.extraPlugins));
  countSkills = dirs: ''$(for d in ${lib.escapeShellArgs dirs}; do find -L "$d" -name SKILL.md -type f; done | sort -u | wc -l)'';
  inventory = pkgs.runCommand "metrics-inventory" { allowedReferences = [ ]; } ''
        {
          ${lib.concatStrings (lib.mapAttrsToList (key: n: "echo ${key} ${toString n}
    ") counts)}
          echo skills ${countSkills skillDirs}
          echo skills_bundled ${countSkills cfg.inventory.bundledSkillDirs}
        } > $out
  '';

  page = pkgs.runCommand "metrics-page" { } ''
    install -D -m 0644 ${./metrics/index.html} $out/index.html
  '';

  # AI and scraper agents that robots.txt names and nginx refuses with a 403. One list feeds both.
  # This stops crawlers that behave well. A scraper can change its User-Agent (docs/METRICS.md).
  # The names come from ai-robots-txt/ai.robots.txt (robots.json at 04e0048, 2026-11-09). nginx
  # matches a name anywhere in the header, so a name that is a common word is left out: Code, Codex,
  # Cursor, Devin, Dot, Instinct, Muse, Operator, Spider, Trae, UseAI, LCC, YaK, and nbot (it is in
  # LinkedInBot). facebookexternalhit is left out because it draws link previews. Versions, domains
  # and other cases of a name (iaskspider/2.0, quillbot.com) are left out: the name matches them.
  blockedAgents = [
    # OpenAI
    "GPTBot"
    "ChatGPT-User"
    "ChatGPT Agent"
    "OAI-SearchBot"
    "OAI-AdsBot"
    "OpenAI"
    # Anthropic
    "ClaudeBot"
    "Claude-User"
    "Claude-SearchBot"
    "Claude-Web"
    "Claude-Agent"
    "Claude-Code"
    "anthropic-ai"
    # Google
    "Google-Extended"
    "Google-CloudVertexBot"
    "CloudVertexBot"
    "Google-Firebase"
    "Google-Agent"
    "GoogleAgent-Mariner"
    "GoogleAgent-URLContext"
    "Google-NotebookLM"
    "NotebookLM"
    "Gemini-Deep-Research"
    "Google-Gemini-CLI"
    "GoogleOther"
    "GoogleOther-Image"
    "GoogleOther-Video"
    # Apple
    "Applebot"
    "Applebot-Extended"
    # Amazon
    "Amazonbot"
    "Amzn-SearchBot"
    "Amzn-User"
    "AmazonBuyForMe"
    "amazon-kendra"
    "amazon-QBusiness"
    "bedrockbot"
    "NovaAct"
    # Meta
    "meta-externalagent"
    "meta-externalfetcher"
    "meta-webindexer"
    "FacebookBot"
    # Microsoft
    "AzureAI-SearchBot"
    # Perplexity
    "PerplexityBot"
    "Perplexity-User"
    # Mistral
    "MistralAI-User"
    "MistralAI-Index"
    "MistralAI-Training"
    # xAI
    "GrokBot"
    "Grok Bot"
    "GrokAppAndroid"
    "xAI-Grok"
    # Cohere
    "cohere-ai"
    "cohere-training-data-crawler"
    # ByteDance
    "Bytespider"
    "TikTokSpider"
    "DoubaoBot"
    # DeepSeek, Moonshot, Alibaba, Baidu, Tencent, Huawei, Zhipu, 01.ai
    "DeepSeekBot"
    "MoonshotBot"
    "KimiBot"
    "Kimi-Agent"
    "Kimi-SearchBot"
    "Kimi-User"
    "QwenBot"
    "TongyiBot"
    "ERNIEBot"
    "YiyanBot"
    "Hunyuan"
    "PanguBot"
    "PetalBot"
    "ChatGLM-Spider"
    "YiBot"
    # Yandex
    "YandexAdditional"
    "YandexAdditionalBot"
    # Ai2, Common Crawl, LAION and other dataset builders
    "AI2Bot"
    "Ai2Bot-Dolma"
    "CCBot"
    "LAIONDownloader"
    "laion-huggingface-processor"
    "img2dataset"
    "FriendlyCrawler"
    "ICC-Crawler"
    "Cotoyogi"
    "SBIntuitionsBot"
    "ISSCyberRiskCrawler"
    "Factset_spyderbot"
    "VelenPublicWebCrawler"
    "Poseidon Research Crawler"
    # Search and answer engines
    "DuckAssistBot"
    "YouBot"
    "PhindBot"
    "Andibot"
    "kagi-fetcher"
    "iAskBot"
    "iaskspider"
    "LinerBot"
    "Bravebot"
    "ExaBot"
    "ExaSearchBot"
    "ExaUser"
    "AddSearchBot"
    "AIWebIndex"
    "Anomura"
    "Channel3Bot"
    "KeenableBot"
    "LinkupBot"
    "ZanistaBot"
    "Querit-SearchBot"
    "QueritBot"
    "Timpibot"
    # Data providers and scraping services
    "Diffbot"
    "Diffbot-User"
    "ImagesiftBot"
    "imageSpider"
    "Omgilibot"
    "omgili"
    "Webzio-Extended"
    "Brightbot"
    "ApifyBot"
    "ApifyWebsiteContentCrawler"
    "FirecrawlAgent"
    "Crawl4AI"
    "Crawlspace"
    "CragCrawler"
    "TavilyBot"
    "ShapBot"
    "Shap-User"
    "TerraCotta"
    "Terra Cotta"
    "HenkBot"
    "BixelBot"
    "AgentDataBot"
    "CloudflareBrowserRenderingCrawler"
    "Cloudflare-AutoRAG"
    "Mozilla-Tabstack"
    "Scrapy"
    "Lightpanda"
    "Panscient"
    "aiHitBot"
    "Awario"
    "EchoboxBot"
    "Echobot Bot"
    "Datenbank Crawler"
    "netEstate Imprint Crawler"
    "Sidetrade indexer bot"
    "Kangaroo Bot"
    "WARDBot"
    "MyCentralAIScraperBot"
    "NagetBot"
    "newsai"
    "AgentTimes"
    # Assistants, agents and coding tools
    "ElevenlabsBot"
    "ElevenlabsCrawler"
    "Manus-User"
    "AGI Agent"
    "TwinAgent"
    "HarkBot"
    "atlassian-bot"
    "KlaviyoAIBot"
    "QualifiedBot"
    "Poggio-Citations"
    "GeistHaus-PageFetcher"
    "CledaraBot"
    "CartAI Agentic Commerce"
    "Payhawk Invoice Fetching Agent"
    "bigsur.ai"
    "BuddyBot"
    "Linguee Bot"
    "QuillBot"
    "SemrushBot-OCOB"
    "SemrushBot-SWA"
    "ScryBot"
    "Thinkbot"
    "wpbot"
    "Reflectionbot"
    "WRTNBot"
    "KunatoCrawler"
    "Aranet-SearchBot"
    "AI2Bot-DeepResearchEval"
    "opencode"
    "qodercli"
  ];
  robotsTxt = pkgs.writeText "metrics-robots.txt" (
    lib.concatMapStrings (agent: "User-agent: ${agent}\nDisallow: /\n\n") blockedAgents
    + "User-agent: *\nDisallow: /\n"
  );

  robotsTag = ''
    add_header X-Robots-Tag "noindex, nofollow, noarchive, noimageindex, noai, noimageai" always;
  '';
  headers = ''
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer always;
    add_header X-Content-Type-Options nosniff always;
    add_header Strict-Transport-Security "max-age=31536000" always;
    ${robotsTag}
  '';

  # What both units share: one fixed user, nothing written but the two folders in /run, no way to
  # gain a right. Not here: ProcSubset=pid, ProtectProc=invisible and PrivateUsers, which hide
  # /proc/stat, other users' processes and their names (docs/METRICS.md, "Hardening").
  sandbox = {
    User = "metrics";
    Group = "metrics";
    UMask = "0022";
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    RestrictNamespaces = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
    ReadWritePaths = [ outDir stateDir ];
    MemoryMax = "64M";
    TasksMax = 64;
    CPUWeight = 20;
    Nice = 10;
    Type = "oneshot";
    # One start and one finish a run would be 17,000 journal lines a day.
    LogLevelMax = "warning";
  };

  timer = what: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2s";
      OnUnitActiveSec = "${toString cfg.collector.interval}s";
      AccuracySec = "1s";
      Unit = "${what}.service";
    };
  };
in
{
  options.piabrota.metrics = {
    name = mkOption {
      type = types.strMatching "[a-z0-9-]*";
      default = "";
      example = "piabrota2";
      description = ''
        The host's name on the page and in its file: `/run/metrics-web/<name>.json`. Never the
        hostname: piabrota2's is still `nixos` until a reboot. The page reads piabrota and piabrota2.
      '';
    };
    label = mkOption {
      type = types.str;
      default = "";
      example = "piabrota2 (KVM 4)";
      description = "What the page calls the host. Empty: the name.";
    };

    inventory.bundledSkillDirs = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = lib.literalExpression ''[ "''${hermes-agent}/skills" ]'';
      description = ''
        Folders of skills that ship inside an agent, counted apart as `skills_bundled`. hermes.nix
        adds Hermes's own. The skills of Hermes's skill folders and plugins are counted by themselves.
      '';
    };

    collector = {
      enable = mkEnableOption "the collector timer: metrics/collect.sh writes this host's file";
      interval = mkOption {
        type = types.ints.between 2 300;
        default = 10;
        description = "Seconds between two runs. The page marks a host offline after 30 s without a new file.";
      };
    };

    web = {
      enable = mkEnableOption "the page and its data behind nginx and TLS, public unless htpasswdFile is set";
      domain = mkOption {
        type = types.str;
        default = "metrics.piabrota.art";
        description = "The name nginx serves the page on. Its DNS A record must point at the box.";
      };
      htpasswdFile = mkOption {
        # A string, not a path: a path literal copies the file into the world-readable store.
        type = types.nullOr types.str;
        default = null;
        example = "/var/lib/hermes-web-secrets/htpasswd";
        description = ''
          The basic-auth users, one `name:bcrypt-hash` line each. `null` (the default) leaves the
          page and its data public. With a path, every request needs a login, and without the file
          every request gets a 500. The Hermes dashboard's file is `config.piabrota.hermesWeb.htpasswdFile`.
        '';
      };
    };

    publish = {
      enable = mkEnableOption "one location on the site's vhost that serves this host's file to the addresses in allowFrom";
      allowFrom = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "187.41.117.18" ];
        description = "IPv4 addresses that may fetch `/_metrics/<name>.json`. Everyone else gets a 403. Not a secret: the file holds no command line.";
      };
    };

    pull = {
      enable = mkEnableOption "the pull timer: metrics/pull.sh fetches another host's published file";
      url = mkOption {
        type = types.str;
        default = "";
        example = "https://www.piabrota.art/_metrics/piabrota.json";
        description = "The address of the other host's file.";
      };
      name = mkOption {
        type = types.strMatching "[a-z0-9-]+";
        default = "piabrota";
        description = "The other host's name: its file is kept as `<name>.json`, and must say `host: <name>`.";
      };
    };
  };

  config = mkMerge [
    (mkIf anyOn {
      users.users.metrics = {
        isSystemUser = true;
        group = "metrics";
      };
      users.groups.metrics = { };
      # In /run: nothing survives a reboot, nothing fills the disk. nginx reads the first folder.
      systemd.tmpfiles.rules = [
        "d ${outDir} 0755 metrics metrics -"
        "d ${stateDir} 0700 metrics metrics -"
      ];
    })

    (mkIf cfg.collector.enable {
      assertions = [{
        assertion = cfg.name != "";
        message = "piabrota.metrics.collector needs piabrota.metrics.name.";
      }];

      systemd.services.metrics-collect = {
        description = "Write this host's metrics file";
        path = [ pkgs.coreutils pkgs.gawk pkgs.glibc.bin ];
        environment = {
          METRICS_NAME = cfg.name;
          METRICS_LABEL = if cfg.label == "" then cfg.name else cfg.label;
          METRICS_INTERVAL = toString cfg.collector.interval;
          OUT_DIR = outDir;
          STATE_DIR = stateDir;
          METRICS_INVENTORY = "${inventory}";
        };
        serviceConfig = sandbox // {
          ExecStart = "${collect}/bin/metrics-collect";
          # Reads /proc and /sys/fs/cgroup only.
          PrivateNetwork = true;
          RestrictAddressFamilies = "AF_UNIX";
        };
      };
      systemd.timers.metrics-collect = timer "metrics-collect";
    })

    (mkIf cfg.pull.enable {
      assertions = [{
        assertion = cfg.pull.url != "";
        message = "piabrota.metrics.pull needs piabrota.metrics.pull.url.";
      }];

      systemd.services.metrics-pull = {
        description = "Fetch ${cfg.pull.name}'s metrics file";
        path = [ pkgs.coreutils pkgs.curl pkgs.gnugrep ];
        environment = {
          METRICS_PULL_URL = cfg.pull.url;
          METRICS_PULL_NAME = cfg.pull.name;
          OUT_DIR = outDir;
        };
        serviceConfig = sandbox // {
          ExecStart = "${pull}/bin/metrics-pull";
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
        };
      };
      systemd.timers.metrics-pull = timer "metrics-pull";
    })

    (mkIf cfg.publish.enable {
      assertions = [
        {
          assertion = cfg.name != "" && cfg.publish.allowFrom != [ ];
          message = "piabrota.metrics.publish needs piabrota.metrics.name and at least one address in allowFrom.";
        }
        {
          assertion = config.piabrota.site.enable;
          message = "piabrota.metrics.publish adds a location to the site's vhost: turn piabrota.site on.";
        }
      ];

      # The vhost is declared in site.nix; this adds one location and changes nothing else.
      services.nginx.virtualHosts.${config.piabrota.site.domain}.locations."= /_metrics/${cfg.name}.json" = {
        alias = "${outDir}/${cfg.name}.json";
        extraConfig = ''
          ${lib.concatMapStrings (ip: "allow ${ip};\n") cfg.publish.allowFrom}
          deny all;
          default_type application/json;
          add_header Cache-Control "no-store" always;
          add_header X-Content-Type-Options nosniff always;
        '';
      };
    })

    (mkIf cfg.web.enable {
      services.nginx = {
        enable = true;
        recommendedTlsSettings = true;
        serverTokens = false;
        # A public page: this limits a scraper. A tab that polls two files every 5 s stays far below it.
        appendHttpConfig = ''
          limit_req_zone $binary_remote_addr zone=metrics_web:1m rate=10r/s;
          limit_conn_zone $binary_remote_addr zone=metrics_conn:1m;
          # The key is the path, a bar and the User-Agent. The first line that matches wins: the
          # robots.txt path is never blocked, so a blocked agent can read it. The second line
          # matches a listed agent, whatever the case. An empty or a normal User-Agent stays 0.
          map "$uri|$http_user_agent" $metrics_blocked_agent {
            default 0;
            "~^/robots\.txt\|" 0;
            "~*\|.*(${lib.concatMapStringsSep "|" lib.escapeRegex blockedAgents})" 1;
          }
        '';
        virtualHosts.${cfg.web.domain} = {
          forceSSL = true;
          enableACME = true;
          basicAuthFile = cfg.web.htpasswdFile;
          root = page;
          extraConfig = ''
            limit_req zone=metrics_web burst=30 nodelay;
            limit_req_status 429;
            limit_conn metrics_conn 20;
            limit_conn_status 429;
            # Only `return` is inside this if, the one use of `if` that nginx documents as safe.
            if ($metrics_blocked_agent) { return 403; }
            ${headers}
          '';
          # add_header in a location drops the server's, so each location repeats the headers. The
          # icon locations come from favicon.nix with four headers of their own: they get the tag here.
          locations = lib.mapAttrs
            (_: location: location // { extraConfig = location.extraConfig + robotsTag; })
            config.piabrota.favicon.locations // {
            "= /robots.txt" = {
              alias = "${robotsTxt}";
              extraConfig = ''
                default_type text/plain;
                add_header Cache-Control "public, max-age=86400" always;
                ${headers}
              '';
            };
            "/data/" = {
              alias = "${outDir}/";
              extraConfig = ''
                add_header Cache-Control "no-store" always;
                ${headers}
              '';
            };
          };
        };
      };

      security.acme = {
        acceptTerms = true;
        defaults.email = config.piabrota.loco.acmeEmail;
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    })
  ];
}
