# KubeSolo (Portainer's single-node Kubernetes) as a trial on this box, behind a flag that is off
# by default. Off, it adds nothing to the system: no package, no unit, no sysctl. On, it runs one
# unit, `kubesolo`, with its state in /var/lib/kubesolo. This is the node layer only; workloads
# live in k8s/ and are applied over an SSH tunnel, never by a deploy. See docs/KUBESOLO.md, which
# also has the rollback.
{ config, lib, pkgs, ... }:
let
  inherit (lib) mkDefault mkEnableOption mkIf mkOption types;
  cfg = config.piabrota.kubesolo;
  yaml = pkgs.formats.yaml { };
  configFile = yaml.generate "kubesolo.yaml" ({
    apiVersion = "kubesolo.io/v1alpha1";
    kind = "Config";
  } // cfg.settings);
  # The admin kubeconfig (root only) copied for the users in `admins`, with the API at 127.0.0.1.
  adminKubeconfig = "/run/kubesolo-admin/kubeconfig";
  k8sShell = pkgs.writeShellScriptBin "k8s" ''
    export KUBECONFIG=${adminKubeconfig}
    export NIXOS_REPO=''${NIXOS_REPO:-$HOME/nix-os}
    exec ${pkgs.bashInteractive}/bin/bash --rcfile ${./kubesolo/k8s.bash} -i
  '';
in
{
  options.piabrota.kubesolo = {
    enable = mkEnableOption "KubeSolo, a single-node Kubernetes, as a trial (docs/KUBESOLO.md)";
    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./kubesolo/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./kubesolo/package.nix { }";
      description = "The kubesolo binary (the static musl release).";
    };
    settings = mkOption {
      inherit (yaml) type;
      default = { };
      description = ''
        KubeSolo's config.yaml, without apiVersion and kind (examples/kubesolo-config.yaml
        upstream has every key). This module sets its own defaults with mkDefault; override any.
        Never a secret here: the file lands in the world-readable store.
      '';
    };
    memoryMax = mkOption {
      type = types.str;
      default = "1G";
      description = "systemd MemoryMax of the unit: KubeSolo, containerd and the shims. Pods run in kubepods.slice; `settings.kubernetes.kubelet.systemReserved` bounds them.";
    };
    hostName = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "srv2108887";
      description = ''
        The host name the box runs with (`hostname`), when it is not networking.hostName (here
        cloud-init sets it). Written to /etc/hosts as 127.0.0.1: the API server reaches the kubelet
        by that name for `kubectl logs`, `exec` and `port-forward`, and KubeSolo's static musl
        resolver fails to look it up through systemd-resolved ("lookup <name>: Try again").
      '';
    };
    healthSnapshot = {
      enable = mkEnableOption "a daily snapshot of the box's health as a ConfigMap, for piabrota/agents' health-digest";
      namespace = mkOption { type = types.str; default = "ax-tasks"; description = "The ConfigMap's namespace."; };
      name = mkOption { type = types.str; default = "health-snapshot"; description = "The ConfigMap's name; its key is `snapshot.md`."; };
      onCalendar = mkOption {
        type = types.str;
        default = "*-*-* 09:20:00 UTC";
        description = "When to take it (systemd OnCalendar): before the digest's CronJob (k8s/agents).";
      };
      units = mkOption {
        type = types.listOf types.str;
        default = [ "sshd" "nginx" "loco-notes" "pgx" "pgx-kube-secrets" "kubesolo" "kubesolo-secret-agents.path" ];
        description = "The units whose state and restarts it lists.";
      };
    };
    secrets = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          namespace = mkOption { type = types.str; description = "The Secret's namespace, created if missing."; };
          envFile = mkOption {
            type = types.str;
            description = "A root-only file on the box with KEY=VALUE lines (no quotes; # comments).";
          };
        };
      });
      default = { };
      example = { agents = { namespace = "ax-tasks"; envFile = "/var/lib/kubesolo-secrets/agents.env"; }; };
      description = ''
        Kubernetes Secrets written from env files on the box, one key per line, so credentials
        never enter the repository or the store. The unit `kubesolo-secret-<name>` applies the
        Secret when the file appears or changes (a path unit watches it) and at boot; without the
        file it does nothing.
      '';
    };
    admins = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "h0ffmann" ];
      description = ''
        Users who run kubectl without sudo. They join the group kubesolo-admin, which reads a copy of
        the admin kubeconfig in /run/kubesolo-admin (refreshed when KubeSolo rewrites it), and get
        kubectl and the `k8s` shell (kubesolo/k8s.bash). That copy is full access to the cluster.
      '';
    };
    cpuQuota = mkOption {
      type = types.str;
      default = "60%";
      description = "systemd CPUQuota of the unit. The box has one vCPU; sshd and nginx keep the rest.";
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "piabrota.kubesolo: the packaged binary is the x86_64 release.";
        }
        {
          # Upstream: no other container engine on the host, or the networking fights.
          assertion = !(config.virtualisation.docker.enable || config.virtualisation.podman.enable || config.virtualisation.containerd.enable);
          message = "piabrota.kubesolo: KubeSolo runs its own containerd; turn docker, podman and containerd off.";
        }
      ];

      piabrota.kubesolo.settings = {
        path = mkDefault "/var/lib/kubesolo";
        network = {
          # Forwarding IPv6 on the host would stop it accepting router advertisements, which
          # cloud-init's network may rely on. Pods get IPv4 only.
          disableIPv6 = mkDefault true;
          # On: every Service of type LoadBalancer gets the public IP, past the NixOS firewall
          # (kube-proxy's DNAT runs before the INPUT chain). Reach pods by port-forward instead.
          loadBalancer.enabled = mkDefault false;
        };
        kubernetes = {
          # The SSH tunnel ends on 127.0.0.1: put it in the API server certificate.
          apiServer.extraSANs = mkDefault [ "127.0.0.1" "localhost" ];
          # The kubelet caps kubepods.slice at the node's memory minus this, so pods together
          # cannot take what sshd, nginx, the Loco apps and KubeSolo itself need. No `cpu` entry:
          # KubeSolo rounds it up to whole CPUs and, on this one-vCPU box, refuses to start ("reserves
          # 1 of this host's 1 CPUs"). CPUQuota and CPUWeight below protect the CPU instead.
          kubelet.systemReserved = mkDefault { memory = "1536Mi"; };
        };
        # One pod less; turn it on when a workload needs a PersistentVolumeClaim.
        storage.localPath.enabled = mkDefault false;
        d2k.enabled = mkDefault false;
        metrics.enabled = mkDefault false;
        logging.pprof = mkDefault false;
        # The configuration is this module; nothing should change it over a socket.
        api.enabled = mkDefault false;
      };

      # Pod networking: a bridge (cni0) with kube-proxy's iptables rules on top.
      boot.kernelModules = [ "br_netfilter" "overlay" ];
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.bridge.bridge-nf-call-iptables" = 1;
      };

      # Pods reach the API server and CoreDNS through cni0; the NixOS firewall would drop that.
      # Nothing is opened to the outside: 6443 (API), 10250 (kubelet) and 10443 (webhook) stay
      # closed, and the API is reached through an SSH tunnel.
      networking.firewall.trustedInterfaces = [ "cni0" ];

      networking.hosts = mkIf (cfg.hostName != null) { "127.0.0.1" = [ cfg.hostName ]; };

      users.groups.kubesolo-admin = mkIf (cfg.admins != [ ]) { members = cfg.admins; };
      environment.systemPackages = mkIf (cfg.admins != [ ]) [ pkgs.kubectl k8sShell ];
      # A kubeconfig in the environment that only the group can read: for everyone else kubectl says
      # permission denied, as it would without it.
      environment.variables.KUBECONFIG = mkIf (cfg.admins != [ ]) adminKubeconfig;
      systemd.tmpfiles.rules = mkIf (cfg.admins != [ ]) [ "d /run/kubesolo-admin 0750 root kubesolo-admin -" ];
      # KubeSolo writes its admin kubeconfig on the first start and when it re-signs; copy it then, and
      # on every boot. The copy points at 127.0.0.1, which the API certificate covers (extraSANs).
      systemd.services.kubesolo-admin-kubeconfig = mkIf (cfg.admins != [ ]) {
        description = "KubeSolo's admin kubeconfig for the kubesolo-admin group";
        wantedBy = [ "multi-user.target" ];
        after = [ "kubesolo.service" "systemd-tmpfiles-setup.service" ];
        serviceConfig.Type = "oneshot";
        script = ''
          src=${cfg.settings.path}/pki/admin/admin.kubeconfig
          [ -f "$src" ] || exit 0
          ${pkgs.gnused}/bin/sed -E 's#(server: https://)[^:/]+(:6443)#\1127.0.0.1\2#' "$src" > ${adminKubeconfig}.new
          chown root:kubesolo-admin ${adminKubeconfig}.new
          chmod 0640 ${adminKubeconfig}.new
          mv ${adminKubeconfig}.new ${adminKubeconfig}
        '';
      };
      systemd.paths.kubesolo-admin-kubeconfig = mkIf (cfg.admins != [ ]) {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = "${cfg.settings.path}/pki/admin/admin.kubeconfig";
      };

      systemd.services.kubesolo = {
        description = "KubeSolo, single-node Kubernetes (trial)";
        documentation = [ "https://github.com/portainer/kubesolo" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "firewall.service" ];
        wants = [ "network-online.target" ];
        # What it runs by name: iptables and nft (kube-proxy, CNI), modprobe, mount, ip.
        path = with pkgs; [ iptables nftables kmod util-linux iproute2 ];
        # No ProtectSystem, PrivateTmp, NoNewPrivileges, SystemCallFilter and the like: containerd
        # and the kubelet run inside this unit and every pod inherits its namespaces and seccomp
        # filters, and the kubelet needs mounts that propagate to the host. The limits that are
        # safe are the resource ones below, the closed firewall and the settings that turn off
        # what listens (load balancer, d2k, metrics, pprof, the config API).
        serviceConfig = {
          ExecStart = "${lib.getExe cfg.package} --config=${configFile}";
          Restart = "always";
          RestartSec = 5;
          # As upstream's unit: the shims start here and manage containers in kubepods.slice; the
          # default KillMode would kill them on a restart and duplicate every pod (upstream #197).
          # It also means stopping the unit leaves pods running; see the rollback in the docs.
          KillMode = "process";
          Delegate = true;
          OOMScoreAdjust = -500;
          LimitNOFILE = 65535;
          StateDirectory = "kubesolo";
          StateDirectoryMode = "0700";
          MemoryMax = cfg.memoryMax;
          CPUQuota = cfg.cpuQuota;
          CPUWeight = 50;
          IOWeight = 50;
        };
      };
    })

    (mkIf cfg.enable {
      # Each Secret by server-side apply with curl and the admin certificate, handed over by systemd
      # with the env file (LoadCredential) to a unit with no user of its own. Not a oneshot: a deploy
      # does not wait for it, and an API still starting is retried every 30 s. It ends once applied,
      # so the path unit can start it again when the file changes.
      systemd.services = lib.mapAttrs'
        (name: s: lib.nameValuePair "kubesolo-secret-${name}" {
          description = "Kubernetes Secret ${s.namespace}/${name} from ${s.envFile}";
          wantedBy = [ "multi-user.target" ];
          after = [ "kubesolo.service" ];
          unitConfig.ConditionPathExists = s.envFile;
          startLimitIntervalSec = 0;
          path = [ pkgs.curl pkgs.jq ];
          script = ''
            set -o pipefail
            apply() {
              curl -fsS -o /dev/null -X PATCH \
                --cacert "$CREDENTIALS_DIRECTORY/ca" --cert "$CREDENTIALS_DIRECTORY/crt" --key "$CREDENTIALS_DIRECTORY/key" \
                -H 'Content-Type: application/apply-patch+yaml' --data-binary @- \
                "https://127.0.0.1:6443$1?fieldManager=kubesolo-secrets&force=true"
            }
            data=$(jq -Rn '[inputs | select(test("^\\s*(#|$)") | not)
              | capture("^(?<k>[A-Za-z_][A-Za-z0-9_.-]*)=(?<v>.*)$") | {(.k): (.v | @base64)}] | add // {}' \
              < "$CREDENTIALS_DIRECTORY/env")
            jq -n --arg ns ${lib.escapeShellArg s.namespace} '{apiVersion: "v1", kind: "Namespace", metadata: {name: $ns}}' \
              | apply /api/v1/namespaces/${lib.escapeShellArg s.namespace}
            jq -n --arg ns ${lib.escapeShellArg s.namespace} --arg name ${lib.escapeShellArg name} --argjson data "$data" \
              '{apiVersion: "v1", kind: "Secret", type: "Opaque", metadata: {name: $name, namespace: $ns}, data: $data}' \
              | apply /api/v1/namespaces/${lib.escapeShellArg s.namespace}/secrets/${lib.escapeShellArg name}
            echo "secret ${s.namespace}/${name}: $(jq -r 'keys | join(", ")' <<<"$data")"
          '';
          serviceConfig = {
            DynamicUser = true;
            Restart = "on-failure";
            RestartSec = 30;
            LoadCredential = [
              "env:${s.envFile}"
              "ca:${cfg.settings.path}/pki/ca/ca.crt"
              "crt:${cfg.settings.path}/pki/admin/admin.crt"
              "key:${cfg.settings.path}/pki/admin/admin.key"
            ];
            CapabilityBoundingSet = "";
            NoNewPrivileges = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
            SystemCallArchitectures = "native";
            SystemCallFilter = [ "@system-service" "~@privileged" ];
          };
        })
        cfg.secrets;
      systemd.paths = lib.mapAttrs'
        (name: s: lib.nameValuePair "kubesolo-secret-${name}" {
          wantedBy = [ "multi-user.target" ];
          pathConfig.PathChanged = s.envFile;
        })
        cfg.secrets;
      systemd.tmpfiles.rules = lib.mapAttrsToList (_: s: "d ${dirOf s.envFile} 0700 root root -") cfg.secrets;
    })

    (mkIf (cfg.enable && cfg.healthSnapshot.enable) {
      # What the box looks like once a day, as Markdown in a ConfigMap that the agents' service
      # account may read (k8s/ax-tasks/rbac.yaml). Written as the Secrets are: curl, server-side
      # apply, the admin certificate through LoadCredential, no user of its own; the journal through
      # the systemd-journal group.
      systemd.services.health-snapshot = {
        description = "The box's health as the ConfigMap ${cfg.healthSnapshot.namespace}/${cfg.healthSnapshot.name}";
        after = [ "kubesolo.service" ];
        path = [ pkgs.curl pkgs.jq pkgs.procps pkgs.coreutils pkgs.gnugrep pkgs.gawk config.systemd.package ];
        script = ''
          set -o pipefail
          api() {
            curl -fsS --cacert "$CREDENTIALS_DIRECTORY/ca" --cert "$CREDENTIALS_DIRECTORY/crt" \
              --key "$CREDENTIALS_DIRECTORY/key" "$@"
          }
          snapshot=$(mktemp)
          {
            echo "# Health snapshot, $(date -u +%Y-%m-%d) at $(date -u +%H:%M) UTC"
            echo
            echo "## System"
            # After a deploy the running system is always newer than the booted one; only a new
            # kernel asks for a reboot.
            echo "NixOS: $(cat /run/current-system/nixos-version)"
            if [ "$(readlink /run/current-system/kernel)" = "$(readlink /run/booted-system/kernel)" ]; then
              echo "kernel: $(uname -r), the one it booted with: no reboot needed"
            else
              echo "kernel: a newer one is deployed than the running $(uname -r): it takes effect at the next reboot"
            fi
            echo "uptime: $(uptime)"
            echo
            echo "## Memory (MiB)"
            free -m
            echo
            echo "## Disk"
            df -h /
            echo
            echo "## Failed units"
            systemctl --failed --no-legend --plain | awk '{print $1}' | grep . || echo "none"
            echo
            echo "## Units that matter"
            for u in ${lib.escapeShellArgs cfg.healthSnapshot.units}; do
              echo "$u: $(systemctl is-active "$u") (restarts: $(systemctl show "$u" -p NRestarts --value))"
            done
            echo
            echo "## Journal errors in the last 24 hours (count, message)"
            journalctl -p err --since -24h -o cat --no-pager | cut -c1-200 | sort | uniq -c | sort -rn | head -n 30 | grep . || echo "none"
            echo
            echo "## Kubernetes pods"
            api https://127.0.0.1:6443/api/v1/pods | jq -r '.items[]
              | "\(.metadata.namespace)/\(.metadata.name): \(.status.phase), restarts \([.status.containerStatuses[]?.restartCount] | add // 0)"'
          } >"$snapshot"
          jq -n --rawfile s "$snapshot" --arg ns ${lib.escapeShellArg cfg.healthSnapshot.namespace} --arg name ${lib.escapeShellArg cfg.healthSnapshot.name} \
            '{apiVersion: "v1", kind: "ConfigMap", metadata: {name: $name, namespace: $ns}, data: {"snapshot.md": $s}}' |
            api -o /dev/null -X PATCH -H 'Content-Type: application/apply-patch+yaml' --data-binary @- \
              "https://127.0.0.1:6443/api/v1/namespaces/${cfg.healthSnapshot.namespace}/configmaps/${cfg.healthSnapshot.name}?fieldManager=health-snapshot&force=true"
          echo "configmap ${cfg.healthSnapshot.namespace}/${cfg.healthSnapshot.name}: $(wc -l <"$snapshot") lines"
          rm -f "$snapshot"
        '';
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          SupplementaryGroups = [ "systemd-journal" ];
          LoadCredential = [
            "ca:${cfg.settings.path}/pki/ca/ca.crt"
            "crt:${cfg.settings.path}/pki/admin/admin.crt"
            "key:${cfg.settings.path}/pki/admin/admin.key"
          ];
          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
          SystemCallArchitectures = "native";
          SystemCallFilter = [ "@system-service" "~@privileged" ];
        };
      };
      systemd.timers.health-snapshot = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.healthSnapshot.onCalendar;
          Persistent = true;
        };
      };
    })
  ];
}
