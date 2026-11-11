# NixOS module system and modularity

The module system is the backbone of NixOS and nix-darwin configuration. Modules declare options, read configuration, and produce system state. Understanding this system is essential for maintainable, composable Nix configurations.

## Module anatomy

A NixOS module is a function that returns an attribute set with `options` and `config`:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.services.myapp;
in {
  options.services.myapp = {
    enable = lib.mkEnableOption "myapp service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on.";
    };

    package = lib.mkPackageOption pkgs "myapp" { };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.myapp = {
      description = "MyApp service";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/myapp --port ${toString cfg.port}";
        DynamicUser = true;
      };
    };
  };
}
```

Key conventions:
- `let cfg = config.<namespace>;` at the top for readability
- `config` block wrapped in `lib.mkIf cfg.enable` so the module is inert when disabled
- Module function takes `{ config, lib, pkgs, ... }` (the `...` is required for forward compatibility)

## Option declaration helpers

### lib.mkEnableOption

Creates a boolean option defaulting to `false`:

```nix
enable = lib.mkEnableOption "my feature";
# equivalent to:
enable = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Whether to enable my feature.";
};
```

### lib.mkOption

Full option declaration with type, default, description, and optionally example:

```nix
lib.mkOption {
  type = lib.types.str;
  default = "hello";
  example = "world";
  description = "A greeting message.";
}
```

### lib.mkPackageOption

Shorthand for a package option with a default from nixpkgs:

```nix
package = lib.mkPackageOption pkgs "nginx" { };
# creates an option defaulting to pkgs.nginx
```

### Common types

| Type | Values |
| :--- | :--- |
| `lib.types.bool` | `true`, `false` |
| `lib.types.str` | string |
| `lib.types.int` | integer |
| `lib.types.port` | 0-65535 |
| `lib.types.path` | store path or string path |
| `lib.types.package` | derivation |
| `lib.types.listOf T` | list of T |
| `lib.types.attrsOf T` | attribute set of T |
| `lib.types.enum [...]` | one of the listed values |
| `lib.types.nullOr T` | T or null |
| `lib.types.submodule { ... }` | nested module |

## Priority and merging

Multiple modules can set the same option. Nix resolves conflicts using priorities:

| Function | Priority | Effect |
| :--- | :--- | :--- |
| `lib.mkDefault value` | 1000 | Low priority; overridden by bare values |
| (bare value) | 100 | Normal priority |
| `lib.mkForce value` | 50 | High priority, overrides most |
| `lib.mkOverride N value` | N | Explicit priority |

```nix
# Module A
services.openssh.enable = lib.mkDefault true;

# Module B (overrides A without mkForce)
services.openssh.enable = false;
```

### lib.mkMerge

Combine multiple config fragments conditionally:

```nix
config = lib.mkMerge [
  (lib.mkIf cfg.enableFeatureA {
    environment.systemPackages = [ pkgs.toolA ];
  })
  (lib.mkIf cfg.enableFeatureB {
    environment.systemPackages = [ pkgs.toolB ];
  })
];
```

## Module composition patterns

### Feature-grouped

Organize modules by feature, keeping related NixOS, nix-darwin, and Home Manager config together:

```text
modules/
  networking/
    default.nix       # NixOS networking module
    darwin.nix         # nix-darwin specifics
  desktop/
    default.nix
    home.nix           # Home Manager user config
  services/
    postgres.nix
    nginx.nix
```

### Host-based

Thin host entrypoints that compose feature modules:

```text
hosts/
  workstation/
    default.nix        # imports relevant modules
    hardware.nix       # hardware-configuration.nix
  server/
    default.nix
    hardware.nix
modules/
  ...
```

Each host imports only the modules it needs:

```nix
# hosts/workstation/default.nix
{ ... }: {
  imports = [
    ./hardware.nix
    ../../modules/desktop
    ../../modules/networking
  ];
}
```

## Overlays

Overlays modify or extend nixpkgs. They are functions `final: prev: { ... }`:

```nix
nixpkgs.overlays = [
  (final: prev: {
    myapp = prev.myapp.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ ./fix.patch ];
    });
  })
];
```

### Overlay scope rules

- **NixOS**: place overlays in `nixpkgs.overlays` within the system configuration.
- **nix-darwin**: same pattern, `nixpkgs.overlays` in the darwin config.
- **Home Manager with `useGlobalPkgs = true`**: overlays in `home.nix` are **silently ignored**. Place them in the host system config so both system and Home Manager see them.
- **Home Manager standalone**: overlays in `nixpkgs.overlays` within home config work as expected.

### When to use overlays

- Patching an upstream package
- Adding a package not in nixpkgs
- Overriding a package version for the whole system

Avoid overlays for configuration (use module options instead) or when `environment.systemPackages` suffices.

## specialArgs and extraSpecialArgs

Pass values from your flake into modules:

```nix
# In flake.nix outputs
nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
  modules = [ ./configuration.nix ];
  specialArgs = { inherit inputs; };
};

# In configuration.nix
{ inputs, config, pkgs, ... }: {
  # inputs.self, inputs.nixpkgs, etc. are available
}
```

For Home Manager:

```nix
home-manager = {
  extraSpecialArgs = { inherit inputs; };
  users.myuser = import ./home.nix;
};
```

## Shared modules across NixOS and nix-darwin

Some options exist in both NixOS and nix-darwin (e.g., `environment.systemPackages`, `programs.zsh.enable`). Write shared modules that work on both:

```nix
{ config, lib, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    git
    ripgrep
    fd
  ];

  programs.zsh.enable = true;
}
```

For platform-specific sections, gate on `pkgs.stdenv.isDarwin` or `pkgs.stdenv.isLinux`:

```nix
config = lib.mkMerge [
  {
    # shared config
  }
  (lib.mkIf pkgs.stdenv.isLinux {
    # NixOS-only
  })
  (lib.mkIf pkgs.stdenv.isDarwin {
    # nix-darwin-only
  })
];
```

Community tools like [nixos-unified](https://github.com/srid/nixos-unified) and [nix-config-modules](https://github.com/chadac/nix-config-modules) provide frameworks for this pattern.

## Anti-patterns

### `with pkgs;` at module top level

```nix
# Bad: pollutes scope, hides where names come from
{ pkgs, ... }: with pkgs; {
  environment.systemPackages = [ git vim tmux ];
}

# Good: explicit
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ git vim tmux ];
  # or fully qualified:
  environment.systemPackages = [ pkgs.git pkgs.vim pkgs.tmux ];
}
```

### `rec` blocks

```nix
# Bad: introduces subtle evaluation issues
rec {
  x = 1;
  y = x + 1;
}

# Good: let binding
let
  x = 1;
  y = x + 1;
in { inherit x y; }
```

### `<nixpkgs>` lookup paths

```nix
# Bad: depends on NIX_PATH, not reproducible
import <nixpkgs> {}

# Good: use flake inputs
# nixpkgs is passed via flake inputs or specialArgs
```

### Excessive `mkForce`

If you need `mkForce` frequently, your module hierarchy has design issues. Prefer `mkDefault` in base modules and bare values in host-specific modules.

## Key references

- [nix.dev module system deep dive](https://nix.dev/tutorials/module-system/deep-dive)
- [NixOS manual: option declarations](https://nixos.org/manual/nixos/stable/#sec-option-declarations)
- [NixOS manual: writing modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [Nixpkgs lib source](https://github.com/NixOS/nixpkgs/tree/master/lib)
