# piabrota.lofi: the lofi bot (lofi/) as the unit `lofi`, in one voice channel of one Discord server,
# playing the files of /var/lib/lofi/music shuffled, without end. The bot token lives only in
# /var/lib/lofi-secrets/lofi.env on the box; without it the unit waits and does nothing. The music
# is copied to the box by hand, never committed (docs/LOFI.md says where legal tracks come from).
{ config, lib, pkgs, ... }:
let
  cfg = config.piabrota.lofi;
  inherit (lib) mkOption types;
  secrets = "/var/lib/lofi-secrets/lofi.env";
in
{
  options.piabrota.lofi = {
    enable = lib.mkEnableOption "the lofi Discord bot";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./lofi { };
      defaultText = lib.literalExpression "pkgs.callPackage ./lofi { }";
    };
    # Not secrets. Left null, they come from the env file on the box with the token.
    guildId = mkOption {
      type = types.nullOr (types.strMatching "[0-9]+");
      default = null;
      description = "The Discord server (guild) ID, or null to read LOFI_GUILD_ID from the env file.";
    };
    channelId = mkOption {
      type = types.nullOr (types.strMatching "[0-9]+");
      default = null;
      description = "The voice channel ID, or null to read LOFI_CHANNEL_ID from the env file.";
    };
    volume = mkOption {
      type = types.numbers.between 0 1;
      default = 0.5;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.lofi = {
      isSystemUser = true;
      group = "lofi";
    };
    users.groups.lofi = { };
    # h0ffmann copies tracks in with scp: the music directory is the lofi group's to write.
    users.users.h0ffmann.extraGroups = [ "lofi" ];

    systemd.tmpfiles.rules = [
      "d /var/lib/lofi-secrets 0700 root root -"
      "d /var/lib/lofi 0750 lofi lofi -"
      "d /var/lib/lofi/music 2775 lofi lofi -"
    ];

    systemd.services.lofi = {
      description = "lofi, a Discord bot that plays music in one voice channel";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # A deploy before the token exists starts nothing; the path unit below starts it once the
      # file is written.
      unitConfig.ConditionPathExists = secrets;
      environment = {
        LOFI_MUSIC_DIR = "/var/lib/lofi/music";
        LOFI_VOLUME = toString cfg.volume;
      }
      // lib.optionalAttrs (cfg.guildId != null) { LOFI_GUILD_ID = cfg.guildId; }
      // lib.optionalAttrs (cfg.channelId != null) { LOFI_CHANNEL_ID = cfg.channelId; };
      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        # DISCORD_TOKEN (and the IDs left null above), written by hand on the box (docs/LOFI.md).
        EnvironmentFile = secrets;
        User = "lofi";
        Group = "lofi";
        Restart = "always";
        RestartSec = 10;
        # 2: a setting is missing or the token is wrong; fix the env file, then `systemctl restart lofi`.
        RestartPreventExitStatus = 2;
        # About 20 MiB resident while it plays; one Opus encode at 48 kHz is a few % of the vCPU.
        MemoryMax = "128M";
        CPUWeight = 50;
        ReadOnlyPaths = [ "/var/lib/lofi" ];
        UMask = "0077";
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        # Voice goes over UDP to Discord's servers; the gateway over TLS.
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    systemd.paths.lofi = {
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathExists = secrets;
    };
  };
}
