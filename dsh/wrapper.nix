# DeepSeek Harness (dsh), the coding worker for Hermes on deepseek-v4.1-flash
# (hermes/skills/hermes-dsh, docs/HERMES.md, "dsh"). The package is nixpkgs'
# `deepseek-harness`; this wrapper adds the OpenCode Go route, the read-only
# profile patch, the key move and the timeout. The patch is in the store, so the
# agent cannot loosen it; the rules appended to the system prompt are
# hermes/dsh-append-system.md.
#
# DSH reads OPENCODE_API_KEY for the custom provider; Hermes's key is
# OPENCODE_GO_API_KEY (hermes.env), and the wrapper moves it without overwriting
# a key a caller already passed. DSH_HOME is under Hermes's state, so the
# headless profile and its sessions survive a deploy.
#
# `ceiling`: the hard stop of `timeout` for every run, like omp's. null turns it
# off for a caller that lives as long as a seat.
{ pkgs
, ceiling ? "35m"
, appendSystemPrompt ? ../hermes/dsh-append-system.md
}:
let
  dsh = pkgs.deepseek-harness;
  # The profile patch is JSON because JSON is YAML and the rules below are a
  # string with newlines: no YAML quoting to get wrong. The order is the order
  # in which the layers apply; the system-prompt entry wins over the headless
  # bundle's own persona prefix.
  patch = pkgs.writeText "hermes-dsh-patch.json" (builtins.toJSON [
    {
      id = "llm-pi-ai";
      config.providers.opencode-go = {
        apiKeyEnv = "OPENCODE_API_KEY";
        api = "openai-completions";
        baseURL = "https://opencode.ai/inference/go/openai/v1";
        # A gateway that rejects the developer role or only knows max_tokens:
        # OpenCode Go answers the same shape the omp provider uses.
        compat = {
          supportsDeveloperRole = false;
          maxTokensField = "max_tokens";
        };
        models = [
          {
            id = "deepseek-v4.1-flash";
            input = [ "text" "image" ];
            compat.thinkingFormat = "deepseek";
            reasoningEfforts = {
              off = null;
              low = "low";
              high = "high";
              max = "max";
            };
          }
        ];
      };
    }
    {
      id = "agent-default-model";
      config = {
        provider = "opencode-go";
        model = "deepseek-v4.1-flash";
        reasoningEffort = "high";
      };
    }
    {
      id = "system-prompt";
      config.personaPrefix = ''
        You are a coding agent powered by the {{model}} model.

      '' + builtins.readFile appendSystemPrompt;
    }
  ]);
in
pkgs.writeShellApplication {
  name = "dsh";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.git
    pkgs.bubblewrap
    dsh
  ];
  text = ''
    set -euo pipefail
    export DSH_HOME="''${DSH_HOME:-/var/lib/hermes/.dsh}"
    # 0.2.1 reads the mode from the environment; the headless profile has no
    # --permission-mode flag. workspace-write is DSH's own default, repeated
    # here so a caller's environment cannot widen it silently.
    export DSH_PERMISSION_MODE="''${DSH_PERMISSION_MODE:-workspace-write}"
    mkdir -p "$DSH_HOME"
    if [ -n "''${OPENCODE_GO_API_KEY:-}" ]; then
      export OPENCODE_API_KEY="$OPENCODE_GO_API_KEY"
    fi
    if [ "''${DSH_CEILING:-}" = "none" ]; then
      exec ${dsh}/bin/dsh --patch ${patch} "$@"
    fi
    exec ${pkgs.coreutils}/bin/timeout -k 30s ${ceiling} \
      ${dsh}/bin/dsh --patch ${patch} "$@"
  '';
}
