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

  config = mkIf cfg.enable {
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
  };
}
