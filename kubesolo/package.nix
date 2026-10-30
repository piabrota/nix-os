# KubeSolo (github.com/portainer/kubesolo) from its release, not from source: the upstream build
# downloads containerd, crun, the CNI plugins and CoreDNS while it runs, which a Nix build cannot
# do. The musl variant is one statically linked file, so it needs no patchelf and no glibc.
# nixpkgs (nixos-26.05) has no kubesolo; bump `version` and `hash` together (SHA256SUMS of the
# release lists the hash in hex).
{ lib, stdenvNoCC, fetchurl }:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "kubesolo";
  version = "1.2.3";

  src = fetchurl {
    url = "https://github.com/portainer/kubesolo/releases/download/v${finalAttrs.version}/kubesolo-v${finalAttrs.version}-linux-amd64-musl.tar.gz";
    hash = "sha256-mXHKTB5JmDOUNP4297myZPl1hJB+AiKDn4NwylI8I5M=";
  };

  # The tarball holds one file, `kubesolo`, at its root.
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # Static and stripped upstream; the fixup phase would only rewrite it for nothing.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 kubesolo $out/bin/kubesolo
    runHook postInstall
  '';

  meta = {
    description = "Single-node Kubernetes in one process: apiserver, controller-manager, kubelet, containerd, Kine on SQLite";
    homepage = "https://github.com/portainer/kubesolo";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "kubesolo";
  };
})
