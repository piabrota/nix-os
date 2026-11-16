# nix-darwin (macOS system management)

nix-darwin brings declarative NixOS-style configuration to macOS. It manages system settings, services, Homebrew, launchd agents/daemons, and shell environments through Nix modules. Applied with `darwin-rebuild switch`.

Canonical docs: [nix-darwin manual](https://nix-darwin.github.io/nix-darwin/manual/) and [nix-darwin README](https://github.com/nix-darwin/nix-darwin).

## Flake-based setup (recommended)

```nix
# flake.nix
{
  description = "My macOS system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # For stable: github:NixOS/nixpkgs/nixpkgs-25.11-darwin
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    # For stable: github:nix-darwin/nix-darwin/nix-darwin-25.11
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, home-manager, ... }: {
    darwinConfigurations."MyHost" = nix-darwin.lib.darwinSystem {
      modules = [
        ./modules/nix-core.nix
        ./modules/system.nix
        ./modules/apps.nix
        home-manager.darwinModules.home-manager
      ];
      specialArgs = { inherit inputs; };
    };
  };
}
```

Replace `"MyHost"` with the output of `scutil --get LocalHostName`.

Set `nixpkgs.hostPlatform` in your system config:
- Apple Silicon: `"aarch64-darwin"`
- Intel: `"x86_64-darwin"`

## Recommended module layout

Split configuration by concern rather than keeping everything in `configuration.nix`. One practical structure:

```text
flake.nix
flake.lock
modules/
  nix-core.nix       # nix settings, GC, substituters, experimental features
  system.nix         # macOS defaults, Touch ID, keyboard
  apps.nix           # Homebrew casks and brews (GUI apps only)
  host-users.nix     # hostname, DNS resolver, user accounts
homes/
  myuser.nix         # Home Manager: packages, shell, git, secrets
secrets/
  secrets.yaml       # sops-encrypted secrets
```

`specialArgs = { inherit inputs; }` threads flake inputs into all modules, making `sops-nix` and other input-derived modules available without `NIX_PATH`.

## First install

```bash
# Generate a starter flake (from scratch):
sudo mkdir -p /etc/nix-darwin
sudo chown $(id -nu):$(id -ng) /etc/nix-darwin
cd /etc/nix-darwin
nix flake init -t nix-darwin/master
sed -i '' "s/simple/$(scutil --get LocalHostName)/" flake.nix

# Build and activate:
sudo nix run nix-darwin/master#darwin-rebuild -- switch
```

After first activation, `darwin-rebuild` is on `PATH`:

```bash
sudo darwin-rebuild switch
```

Build without switching first to check for errors:

```bash
sudo darwin-rebuild build --flake .#MyHost
```

## Channel-based setup (legacy)

```bash
sudo nix-channel --add https://github.com/nix-darwin/nix-darwin/archive/master.tar.gz darwin
sudo nix-channel --update
nix-build '<darwin>' -A darwin-rebuild
sudo ./result/bin/darwin-rebuild switch -I darwin-config=/etc/nix-darwin/configuration.nix
```

Update with `sudo nix-channel --update && sudo darwin-rebuild switch`.

## Homebrew: GUI apps only

Use Homebrew for GUI applications and casks that are not available as native Nix packages. Do not use Homebrew formulae to duplicate what is already in nixpkgs -- install CLI tools and libraries through `environment.systemPackages` or Home Manager instead.

Good uses for `homebrew.brews`:
- Tools that require macOS-specific system integration not wired up in nixpkgs
- Build tools only available as Homebrew formulas

Everything else belongs in nixpkgs.

```nix
# modules/apps.nix
{ ... }: {
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = "zap";   # uninstall unlisted formulae/casks on activation
      upgrade = true;
    };

    # Only GUI apps that have no equivalent Nix package
    casks = [
      "aerospace"      # tiling window manager (darwin-only, limited nixpkgs support)
      "iterm2"
      "docker"
      "firefox"
    ];

    masApps = {
      Tailscale = 1475387142;
    };

    # brews: keep this list short and justified
    # If the package is in nixpkgs, use pkgs.* instead
    brews = [ ];
  };
}
```

Removing an entry also uninstalls it when `cleanup = "zap"`.

## Nix settings (nix-core)

```nix
# modules/nix-core.nix
{ pkgs, ... }: {
  services.nix-daemon.enable = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBc="
    ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    interval = { Weekday = 0; Hour = 0; Minute = 0; };
    options = "--delete-older-than 30d";
  };
}
```

## System defaults

```nix
# modules/system.nix
{ ... }: {
  system.defaults = {
    dock.autohide = true;
    dock.mru-spaces = false;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllFiles = true;
    NSGlobalDomain.InitialKeyRepeat = 15;
    NSGlobalDomain.KeyRepeat = 2;
  };

  # Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;
}
```

Browse available options: `man 5 configuration.nix` or the [online manual](https://nix-darwin.github.io/nix-darwin/manual/).

## Launchd services

```nix
launchd.user.agents.my-agent = {
  serviceConfig = {
    ProgramArguments = [ "/usr/bin/env" "echo" "hello" ];
    StartInterval = 3600;
    StandardOutPath = "/tmp/my-agent.log";
    StandardErrorPath = "/tmp/my-agent.err";
  };
};
```

System-wide daemons use `launchd.daemons.*`. Keys map directly to macOS launchd plist keys.

## Using Lix instead of Nix

```nix
nix.package = pkgs.lix;
```

The installer choice does not lock you in; nix-darwin manages the Nix installation and defaults to upstream Nix.

## Home Manager integration

```nix
home-manager = {
  useGlobalPkgs = true;
  useUserPackages = true;
  users.myuser = import ./homes/myuser.nix;
  extraSpecialArgs = { inherit inputs; };
};
```

**Overlay scope rule**: when `useGlobalPkgs = true`, overlays in `home.nix` are silently ignored. Place overlays in `nixpkgs.overlays` in the system config so both system packages and Home Manager packages see them.

## Secrets with sops-nix

Encrypt with an age key derived from a YubiKey (PIV slot via `age-plugin-yubikey`), store encrypted YAML in `secrets/`, decrypt at Home Manager activation:

```nix
# homes/myuser.nix (Home Manager)
{ inputs, config, pkgs, ... }: {
  imports = [ inputs.sops-nix.homeManagerModules.sops ];

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    secrets.my-token = {
      path = "${config.home.homeDirectory}/.config/myapp/token";
    };
  };
}
```

Secrets decrypt to paths accessible to the user at activation time. Never commit plaintext secrets; the `secrets/` directory should contain only encrypted YAML.

## Common mistakes

| Mistake | Fix |
| :--- | :--- |
| Wrong `hostPlatform` | `uname -m`: `arm64` = `aarch64-darwin`, `x86_64` = `x86_64-darwin` |
| Running `darwin-rebuild` without `sudo` | Most system changes require root |
| Homebrew duplicating nixpkgs packages | Remove from `brews`, add to `environment.systemPackages` |
| Overlays in `home.nix` with `useGlobalPkgs` | Move to `nixpkgs.overlays` in the system config |
| Forgetting `follows` for shared inputs | Multiple nixpkgs instances waste eval time and disk |
| Stale generations accumulating | `sudo nix-collect-garbage -d` periodically |

## Uninstalling nix-darwin

```bash
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin#darwin-uninstaller
```

Fallback if the above fails: `sudo darwin-uninstaller`.

## Key references

- [nix-darwin README](https://github.com/nix-darwin/nix-darwin)
- [nix-darwin manual (options)](https://nix-darwin.github.io/nix-darwin/manual/)
- [Home Manager manual](https://nix-community.github.io/home-manager/)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [kaynix](https://github.com/kaynetik/kaynix)
- Matrix: [#macos:nixos.org](https://matrix.to/#/#macos:nixos.org), [#nix-darwin-dev:nixos.org](https://matrix.to/#/#nix-darwin-dev:nixos.org)
