# oh-my-pi (omp), the coding agent Hermes hands repository work to (hermes/skills/hermes-omp,
# docs/HERMES.md, "omp"), and Paperclip's pi_local adapter through paperclip/pi-to-omp.sh. Hermes's
# deny list and tripwire see only the outer `omp` command, so omp gets its own rules: hermes/omp.yml,
# a read-only config overlay. This wrapper is the only omp on Hermes's PATH. omp reads
# ANTHROPIC_OAUTH_TOKEN; Hermes's token is CLAUDE_CODE_OAUTH_TOKEN, the same subscription. omp runs
# in its caller's cgroup: choom makes the kernel's OOM killer pick omp before the gateway.
#
# `ceiling`: a hard stop of `timeout` for every run, whatever flags the caller gives: a restart
# killed a long run on 2026-11-04, and the ceiling bounds the loss and the cost. SIGTERM first,
# SIGKILL 30 seconds later. null turns it off: an OpenRig seat (`omp --mode rpc` under OpenRig's
# pi-runner) lives as long as its rig, and a ceiling would kill the seat in the middle of its work.
# `appendSystemPrompt`: the rules appended to omp's system prompt; a seat takes
# hermes/omp-seat-append-system.md.
#
# OpenRig's runner gives omp a deny-by-default environment: of the Anthropic credentials it passes
# only ANTHROPIC_API_KEY, and only for a seat whose model is `anthropic/...` (pi-runner-protocol.ts at
# v0.7.7). A subscription token (sk-ant-oat...) in that variable is moved to ANTHROPIC_OAUTH_TOKEN, so
# omp signs in with the subscription and never sends it as an API key.
{ pkgs
, ceiling ? "35m"
, appendSystemPrompt ? ../hermes/omp-append-system.md
}:
let
  omp = "${pkgs.callPackage ./package.nix { }}/bin/omp";
  run =
    if ceiling == null then
      "exec ${pkgs.util-linux}/bin/choom -n 500 -- ${omp}"
    else
      "exec ${pkgs.coreutils}/bin/timeout --signal=TERM --kill-after=30s ${ceiling} ${pkgs.util-linux}/bin/choom -n 500 -- ${omp}";
in
pkgs.writeShellApplication {
  name = "omp";
  text = ''
    export PI_CONFIG_FILES=${../hermes/omp.yml}
    if [ -z "''${ANTHROPIC_OAUTH_TOKEN:-}" ] && [ -z "''${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
      case "''${ANTHROPIC_API_KEY:-}" in
        sk-ant-oat*)
          export ANTHROPIC_OAUTH_TOKEN="$ANTHROPIC_API_KEY"
          unset ANTHROPIC_API_KEY
          ;;
      esac
    fi
    export ANTHROPIC_OAUTH_TOKEN="''${ANTHROPIC_OAUTH_TOKEN:-''${CLAUDE_CODE_OAUTH_TOKEN:-}}"
    export OTEL_SDK_DISABLED=true PI_NO_TITLE=1 PI_PY=0 PI_JS=0
    ${run} --append-system-prompt ${appendSystemPrompt} "$@"
  '';
}
