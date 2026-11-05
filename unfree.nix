# The unfree packages this system may use, by name. `allowUnfree` stays off: a package that is not
# in the list below fails to evaluate. Add a name here only with the owner's yes, and say who asked,
# why and when, as the entry below does.
{ lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    # Claude Code (`claude`), Anthropic's CLI. Asked by the owner on 2026-11-05, so that the seats of
    # the OpenRig rig wave-forecaster-dev run it as a pure Claude Code harness (docs/RUNTIMES.md).
    # It is the only exception.
    "claude-code"
  ];
}
