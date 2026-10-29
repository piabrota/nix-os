# Derivations and packaging

A derivation is a specification for running an executable on precisely defined inputs to produce outputs deterministically. The same derivation with unchanged inputs always produces the same store path. Everything in Nix ultimately evaluates to derivations.

## Core concepts

```text
  Nix expression (.nix)
        |
    evaluation
        |
  derivation (.drv in /nix/store)
        |
    build (sandboxed)
        |
  output (store path: /nix/store/<hash>-<name>)
```

A derivation requires:
- **name**: symbolic identifier (in nixpkgs: `pname` + `version`)
- **system**: target platform (`x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`)
- **builder**: executable that performs the build

## stdenv.mkDerivation

The standard way to create packages in nixpkgs. Wraps the low-level `derivation` builtin with a build environment, phases, and utilities.

```nix
{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "example";
  version = "1.2.3";

  src = fetchFromGitHub {
    owner = "someone";
    repo = "example";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ ];   # build-time tools (cmake, pkg-config, ...)
  buildInputs = [ ];         # libraries linked against

  meta = with lib; {
    description = "An example package";
    homepage = "https://github.com/someone/example";
    license = licenses.mit;
    maintainers = [ maintainers.alice ];
    platforms = platforms.unix;
    mainProgram = "example";
  };
}
```

### Build phases

`stdenv.mkDerivation` runs phases in order. Override or extend them as needed:

1. `unpackPhase` -- extracts `src`
2. `patchPhase` -- applies `patches` list
3. `configurePhase` -- runs `./configure` (autotools) or equivalent
4. `buildPhase` -- runs `make` (or equivalent)
5. `checkPhase` -- runs tests (disabled by default; enable with `doCheck = true`)
6. `installPhase` -- runs `make install`
7. `fixupPhase` -- patches ELF binaries, wraps scripts

Override a phase:

```nix
buildPhase = ''
  cargo build --release
'';
installPhase = ''
  mkdir -p $out/bin
  cp target/release/example $out/bin/
'';
```

## Fetchers

All fetchers create fixed-output derivations. The hash identifies the output.

| Fetcher | Use case |
| :--- | :--- |
| `fetchurl` | Direct URL download (unaltered) |
| `fetchzip` | URL download with archive extraction |
| `fetchFromGitHub` | GitHub repos; accepts `owner`, `repo`, `rev` or `tag` |
| `fetchFromGitLab` | GitLab repos |
| `fetchgit` | Any git repo (supports submodules, LFS) |
| `fetchCrate` | crates.io |

`fetchFromGitHub` prefers `fetchzip` internally for hash stability. Use `fetchgit` behavior with `fetchSubmodules = true` or `deepClone = true`.

### Updating hashes

```bash
# Prefetch a GitHub source:
nix-prefetch-url --unpack "https://github.com/owner/repo/archive/v1.2.3.tar.gz"

# Or use nix hash with a fetcher expression:
nix hash convert --hash-algo sha256 --to sri <hex-hash>

# For cargo/go/npm vendor hashes, set hash = "" first, build, and copy from error.
```

## Language-specific builders

### Rust (buildRustPackage)

```nix
{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "mytool";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "someone";
    repo = "mytool";
    rev = "v${version}";
    hash = "sha256-...";
  };

  cargoHash = "sha256-...";

  meta = { ... };
}
```

`cargoHash` pins the Cargo.lock vendor output. Set to `""` first, build to get the correct hash.

### Go (buildGoModule)

```nix
{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "gotool";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "someone";
    repo = "gotool";
    rev = "v${version}";
    hash = "sha256-...";
  };

  vendorHash = "sha256-...";
  # or vendorHash = null; if the repo vendors dependencies

  meta = { ... };
}
```

### Node.js (buildNpmPackage)

```nix
{ lib, buildNpmPackage, fetchFromGitHub }:

buildNpmPackage rec {
  pname = "nodeapp";
  version = "2.0.0";

  src = fetchFromGitHub {
    owner = "someone";
    repo = "nodeapp";
    rev = "v${version}";
    hash = "sha256-...";
  };

  npmDepsHash = "sha256-...";

  meta = { ... };
}
```

### Python (buildPythonPackage)

```nix
{ lib, python3Packages, fetchPypi }:

python3Packages.buildPythonPackage rec {
  pname = "mylib";
  version = "0.5.0";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-...";
  };

  propagatedBuildInputs = with python3Packages; [ requests ];

  meta = { ... };
}
```

## pkgs/by-name (RFC 140)

The preferred location for new top-level packages. Directory structure:

```text
pkgs/by-name/
  he/
    hello/
      package.nix
  my/
    mytool/
      package.nix
```

Rules:
- `${shard}` is the lowercased first two letters of `${name}`
- Names: ASCII `a-z`, `A-Z`, `0-9`, `-`, `_`; no leading digit or `-`
- Names must be unique when lowercased
- Package must be a derivation defined with `callPackage`
- Top-level packages only (not package sets like `python3Packages.*`)
- No need to edit `all-packages.nix` for `pkgs/by-name` packages

Validation: `nixpkgs-vet` (v0.2.0) runs in CI and can be invoked locally via `ci/nixpkgs-vet.sh`.

## meta attributes

| Attribute | Required | Purpose |
| :--- | :--- | :--- |
| `description` | Yes | One-line summary (no period at end) |
| `homepage` | Yes | Upstream project URL |
| `license` | Yes | From `lib.licenses.*` |
| `maintainers` | Yes | From `lib.maintainers.*` |
| `platforms` | Recommended | `lib.platforms.unix`, `.linux`, `.darwin`, or explicit list |
| `mainProgram` | Recommended | Binary name for `nix run` |
| `changelog` | Optional | URL to changelog |
| `longDescription` | Optional | Multi-line description |
| `broken` | Optional | `true` to mark as broken |
| `knownVulnerabilities` | Optional | List of CVE strings |

## Passthru tests

Attach tests that run as part of `nix-build -A package.tests`:

```nix
passthru.tests = {
  version = testers.testVersion { package = mytool; };
  integration = nixosTests.mytool;
};
```

## Cross-compilation

nixpkgs provides cross-compilation through `pkgsCross`:

```bash
nix-build '<nixpkgs>' -A pkgsCross.aarch64-multiplatform.hello
```

In a package, use `nativeBuildInputs` for build-time tools (run on the build host) and `buildInputs` for runtime dependencies (built for the target).

## Key references

- [Nixpkgs manual: stdenv](https://nixos.org/manual/nixpkgs/stable/#chap-stdenv)
- [Nixpkgs manual: languages and frameworks](https://nixos.org/manual/nixpkgs/stable/#chap-language-support)
- [pkgs/README.md](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md)
- [RFC 140](https://github.com/NixOS/rfcs/blob/master/rfcs/0140-simple-package-paths.md)
- [noogle.dev](https://noogle.dev/) (Nix function search)
