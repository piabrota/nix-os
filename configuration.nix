# NixOS system configuration for the Hostinger KVM template.
# Built into a qcow2 by image.nix via nixpkgs' make-disk-image (no nixos-infect).
{ lib, pkgs, modulesPath, ... }:
{
  imports = [
    # virtio_scsi/virtio_blk etc. in the initrd so the image boots on Proxmox.
    "${modulesPath}/profiles/qemu-guest.nix"
    ./piabrota.nix
    ./tools.nix
    ./deploy.nix
    ./loco.nix
    ./site.nix
    ./apps.nix
    # A trial of single-node Kubernetes (docs/KUBESOLO.md), turned on below.
    ./kubesolo.nix
    # A Postgres-compatible database for rax's store (docs/PGX.md), turned on below.
    ./pgx.nix
  ];

  # BIOS/SeaBIOS GRUB on the single legacy (MBR) disk. `device` is the VPS disk (scsi0),
  # used when the customer runs nixos-rebuild; image.nix overrides it for the build VM.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.efiSupport = false;
  boot.loader.timeout = 1;

  # Root is the single labelled partition make-disk-image creates; grow it to the
  # provisioned disk size on first boot (Hostinger plans resize the disk).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  boot.growPartition = true;

  # Serial console for Proxmox serial0 + memory hotplug, mirroring GRUB_CMDLINE_LINUX
  # in the other templates.
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200" "earlyprintk=ttyS0,115200" "consoleblank=0" "memhp_default_state=online" ];

  # QEMU guest agent: how Proxmox/hVPS talk to the VM (udev-started qemu-guest-agent.service).
  services.qemuGuest.enable = true;

  # Provisioning via the Proxmox cloud-init drive (ide2), same as every other template.
  # Proxmox exposes config through the NoCloud datasource; pin it (NixOS ships no default).
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;
  services.cloud-init.settings.datasource_list = [ "NoCloud" "ConfigDrive" ];
  # The keys-to-console module's helper (write-ssh-key-fingerprints) isn't shipped in NixOS's
  # cloud-init package, so it errors and downgrades cloud-init to "degraded done" (exit 2).
  # It only prints host-key fingerprints to the console — disable it for a clean exit 0.
  services.cloud-init.settings.ssh.emit_keys_to_console = false;
  # cloud-init owns IP assignment, so DHCP must be off (otherwise it races cloud-init).
  networking.useDHCP = lib.mkForce false;

  # hVPS drives provisioning by running bare-name commands (sh, cloud-init, chpasswd, ...)
  # through the guest agent, which resolves them on the *agent's* PATH. NixOS gives services a
  # minimal PATH and keeps `sh` only in /bin, so point the agent at the full system environment
  # (setuid wrappers + system path + /bin for sh). Without this, provisioning fails with e.g.
  # "cloud-init: No such file or directory" or "sh: No such file or directory".
  # cloud-init (provisioning CLI) plus the common tools the Debian/Ubuntu templates ship and
  # that hVPS verification invokes by bare name (e.g. `dig` for a DNS check).
  environment.systemPackages = with pkgs; [
    cloud-init
    dnsutils   # dig, nslookup, host
    nettools   # ifconfig, netstat, route (net-tools parity)
    curl
    wget
    nano
  ];
  systemd.services.qemu-guest-agent.environment.PATH =
    lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/bin";

  # The static site on www.piabrota.art (site.nix). DNS points both names at this box.
  piabrota.site.enable = true;
  # Single-node Kubernetes, on for a trial (kubesolo.nix, docs/KUBESOLO.md). Before the merge that
  # turns it on, take a Hostinger snapshot; to undo, see the rollback in docs/KUBESOLO.md.
  piabrota.kubesolo.enable = true;
  # PGX, the Postgres that rax's store on KubeSolo uses instead of a PostgreSQL server or Docker
  # (pgx.nix, docs/PGX.md). Not for data you keep: that stays in SQLite.
  piabrota.pgx.enable = true;
  # rax's store URL as the Secret ax-system/ax-store (k8s/rax), written on the box from `pgx url ax`.
  piabrota.pgx.kubeSecrets.ax-store = { namespace = "ax-system"; database = "ax"; };

  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = lib.mkDefault "yes";

  system.stateVersion = "26.05";
}
