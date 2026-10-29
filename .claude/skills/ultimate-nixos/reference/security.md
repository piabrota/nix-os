# NixOS security

Hardening, secrets management, and sandboxing for NixOS. Declarative configuration and immutable store paths enable reproducible and auditable security postures.

## Hardened profile

NixOS ships a hardened profile that enables conservative security defaults:

```nix
{ modulesPath, ... }: {
  imports = [ "${modulesPath}/profiles/hardened.nix" ];
}
```

What it enables:
- Hardened Linux kernel (`boot.kernelPackages = pkgs.linuxPackages_hardened`)
- AppArmor with `killUnconfinedConfinables`
- Kernel parameter hardening (`slab_nomerge`, `page_poison`, `init_on_alloc`, `init_on_free`)
- Module blacklisting for obscure filesystems and protocols
- Restricted `/proc` and `/sys` visibility

**Tradeoffs**:
- User namespaces disabled by default (`security.allowUserNamespaces = false`), which prevents unprivileged Nix builds. Override with `security.allowUserNamespaces = true` if needed.
- Some performance overhead from hardened kernel and memory initializations.
- Bluetooth, Thunderbolt, and FireWire modules are blacklisted.

## Firewall

```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 ];
  allowedUDPPorts = [ ];
  allowPing = true;
};
```

NixOS 25.11 added FirewallD support as an alternative:

```nix
services.firewalld.enable = true;
```

## AppArmor

```nix
security.apparmor = {
  enable = true;
  killUnconfinedConfinables = true;
  policies = {
    my-service = {
      enforce = true;     # or "complain" or "disable"
      profile = ''
        /usr/bin/my-service {
          # AppArmor rules
        }
      '';
    };
  };
};
```

A reboot is required to activate AppArmor in the kernel on first enable. Note: neither SELinux nor AppArmor is fully mature on NixOS due to the immutable `/nix/store` making file-labeling difficult. AppArmor is better supported than SELinux.

## Systemd service sandboxing

Harden individual services with systemd security options:

```nix
systemd.services.my-service = {
  serviceConfig = {
    DynamicUser = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    NoNewPrivileges = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    RestrictNamespaces = true;
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    CapabilityBoundingSet = [ "" ];       # drop all capabilities
    SystemCallFilter = [ "@system-service" ];
    SystemCallArchitectures = "native";
    ReadWritePaths = [ "/var/lib/my-service" ];
  };
};
```

Use `systemd-analyze security my-service.service` to audit exposure scores.

## Secrets management

Never store secrets in the Nix store -- store paths are world-readable.

### sops-nix

Encrypts secrets with age keys. Decrypts at activation time.

```nix
# flake.nix inputs
sops-nix.url = "github:Mic92/sops-nix";
sops-nix.inputs.nixpkgs.follows = "nixpkgs";

# configuration.nix
sops = {
  defaultSopsFile = ./secrets/secrets.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";

  secrets.db-password = {
    owner = "postgres";
    group = "postgres";
    mode = "0400";
  };
};
```

Secrets decrypt to `/run/secrets/<name>` by default. Generate age keys:

```bash
age-keygen -o /var/lib/sops-nix/key.txt
```

Encrypt:

```bash
sops --age $(age-keygen -y /var/lib/sops-nix/key.txt) secrets/secrets.yaml
```

### agenix

Encrypts with age using SSH host/user keys. Lighter weight than sops-nix.

```nix
age.secrets.db-password = {
  file = ./secrets/db-password.age;
  owner = "postgres";
  group = "postgres";
  mode = "0400";
};
```

Encrypt:

```bash
agenix -e secrets/db-password.age
```

### Comparison

| Feature | sops-nix | agenix |
| :--- | :--- | :--- |
| Key type | age keys (separate from SSH) | age via SSH keys |
| Secret format | YAML, JSON, env, binary | Single file per secret |
| Multi-key encryption | Yes (multiple recipients) | Yes (via `secrets.nix`) |
| Editor integration | `sops` CLI opens in `$EDITOR` | `agenix -e` opens in `$EDITOR` |
| Complexity | More features, more config | Minimal, fewer moving parts |

Both decrypt secrets to `/run/secrets/` at activation. Choose based on existing key infrastructure.

## Disk encryption and secure boot

### LUKS

```nix
boot.initrd.luks.devices.cryptroot = {
  device = "/dev/disk/by-uuid/...";
  preLVM = true;
};
```

### Secure boot

NixOS 25.11 added Limine secure boot support alongside the existing systemd-boot and rEFInd options:

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
```

For secure boot with Lanzaboote (community project):

```nix
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/etc/secureboot";
};
```

## Impermanence pattern

Run the root filesystem on tmpfs so state resets on reboot. Persist only declared paths:

```nix
environment.persistence."/persist" = {
  directories = [
    "/var/log"
    "/var/lib/nixos"
    "/var/lib/systemd"
    "/etc/NetworkManager/system-connections"
  ];
  files = [
    "/etc/machine-id"
  ];
};
```

No undeclared state accumulates between reboots. Requires the [impermanence](https://github.com/nix-community/impermanence) module.

## Nix build sandbox

Nix builds run in a sandbox by default on Linux (`sandbox = true` in `nix.conf`). The sandbox:
- Restricts network access during builds
- Provides a minimal filesystem (only declared inputs)
- Prevents builds from reading host state

Fixed-output derivations (fetchers) are allowed network access because their output is verified by hash.

macOS sandboxing is more limited but enabled by default on nix-darwin.

## Supply chain

- Pin all flake inputs via `flake.lock`.
- Use SRI hashes (`sha256-...=`) for fetcher sources.
- Review dependency updates (`nix flake update` diffs).
- Consider `nix store verify --all` to check store path signatures.
- Reproducible builds: the same inputs should produce bit-identical outputs. nixpkgs CI tests this for core packages.

## Key references

- [NixOS hardened profile source](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/profiles/hardened.nix)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [agenix](https://github.com/ryantm/agenix)
- [impermanence](https://github.com/nix-community/impermanence)
- [Lanzaboote](https://github.com/nix-community/lanzaboote)
- [NixOS wiki: comparison of secret managing schemes](https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes)
