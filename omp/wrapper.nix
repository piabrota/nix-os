# oh-my-pi (omp), the coding agent Hermes hands repository work to (hermes/skills/hermes-omp,
# docs/HERMES.md, "omp"). Hermes's
# deny list and tripwire see only the outer `omp` command, so omp gets its own rules: hermes/omp.yml,
# a read-only config overlay. This wrapper is the only omp on Hermes's PATH. omp reads
# OPENCODE_API_KEY for opencode-go (docs/providers.md at v18.16.0); Hermes's key is
# OPENCODE_GO_API_KEY (hermes.env), and `piabrota omp` moves it. The Claude credential variables are
# unset, so a stale Claude token never makes another provider selectable. omp runs
# in its caller's cgroup: choom makes the kernel's OOM killer pick omp before the gateway.
#
# `ceiling`: a hard stop of `timeout` for every run, whatever flags the caller gives: a restart
# killed a long run on 2026-11-04, and the ceiling bounds the loss and the cost. SIGTERM first,
# SIGKILL 30 seconds later. null turns it off: an OpenRig seat (`omp --mode rpc` under OpenRig's
# pi-runner) lives as long as its rig, and a ceiling would kill the seat in the middle of its work.
# `appendSystemPrompt`: the rules appended to omp's system prompt; a seat takes
# hermes/omp-seat-append-system.md.
#
# OpenRig's runner gives omp a deny-by-default environment: of the OpenCode credentials it passes
# only OPENCODE_API_KEY, and only for a seat whose model is `opencode-go/...` (pi-runner-protocol.ts
# at v0.7.7). The wrapper sets OPENCODE_API_KEY only when the caller has OPENCODE_GO_API_KEY, so it
# never overwrites the key a seat's runner already passed.
{ pkgs
, ceiling ? "35m"
, appendSystemPrompt ? ../hermes/omp-append-system.md
}:
let
  scripts = pkgs.callPackage ../scala { };
in
# `piabrota omp` (scala/scripts/Wrappers.scala) does the token moves and execs the programs below.
scripts.command {
  name = "omp";
  env = {
    OMP_CONFIG = "${../hermes/omp.yml}";
    OMP_APPEND = "${appendSystemPrompt}";
    OMP_CEILING = if ceiling == null then "none" else ceiling;
    OMP_BIN = "${pkgs.callPackage ./package.nix { }}/bin/omp";
    OMP_TIMEOUT = "${pkgs.coreutils}/bin/timeout";
    OMP_CHOOM = "${pkgs.util-linux}/bin/choom";
  };
}
