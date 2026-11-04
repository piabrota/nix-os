# oh-my-pi (omp), the coding agent Hermes hands repository work to (hermes/skills/hermes-omp,
# docs/HERMES.md, "omp"), and Paperclip's pi_local adapter through paperclip/pi-to-omp.sh. Hermes's
# deny list and tripwire see only the outer `omp` command, so omp gets its own rules: hermes/omp.yml,
# a read-only config overlay. This wrapper is the only omp on Hermes's PATH. omp reads
# ANTHROPIC_OAUTH_TOKEN; Hermes's token is CLAUDE_CODE_OAUTH_TOKEN, the same subscription. omp runs
# in its caller's cgroup: choom makes the kernel's OOM killer pick omp before the gateway. timeout is
# a hard ceiling of 35 minutes for every run, whatever flags the caller gives: a restart killed a
# long run on 2026-11-04, and the ceiling bounds the loss and the cost. SIGTERM first, SIGKILL 30
# seconds later.
{ pkgs }:
pkgs.writeShellApplication {
  name = "omp";
  text = ''
    export PI_CONFIG_FILES=${../hermes/omp.yml}
    export ANTHROPIC_OAUTH_TOKEN="''${ANTHROPIC_OAUTH_TOKEN:-''${CLAUDE_CODE_OAUTH_TOKEN:-}}"
    export OTEL_SDK_DISABLED=true PI_NO_TITLE=1 PI_PY=0 PI_JS=0
    exec ${pkgs.coreutils}/bin/timeout --signal=TERM --kill-after=30s 35m ${pkgs.util-linux}/bin/choom -n 500 -- ${pkgs.callPackage ./package.nix { }}/bin/omp --append-system-prompt ${../hermes/omp-append-system.md} "$@"
  '';
}
