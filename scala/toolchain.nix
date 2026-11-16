# The JDK and scala-cli of scala/: the newest each has (the owner, 2026-11-14). nixos-26.05's
# newest JDK is 25; its scala-cli is 1.14.0, so this takes the 1.19.0 release binary instead. The
# JDK only compiles: no JVM reaches a box. The Nix build and `nix develop .#scala` both use this.
{ fetchurl, jdk25, scala-cli }:
rec {
  jdk = jdk25;
  scalaCli = (scala-cli.override { jre = jdk; }).overrideAttrs (_: rec {
    version = "1.19.0";
    src = fetchurl {
      url = "https://github.com/Virtuslab/scala-cli/releases/download/v${version}/scala-cli-x86_64-pc-linux.gz";
      hash = "sha256-oavEFkVDk3ueuYtkCYPU0whK7pif+gMoapJrGi/hQlQ=";
    };
  });
}
