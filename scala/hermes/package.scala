package piabrota.hermes

import piabrota.lib.Command

/** The commands of hermes/: the gateway's supervisor, the cron jobs and the skills' programs. */
val commands: List[Command] = List(
  Command("gateway-wrapper", "the main process of hermes-agent: restarts the gateway on exit 75", GatewayWrapper.run),
  Command("refresh-grid", "cron job: refresh the data of the grid of piabrota/room in a PR", RefreshGrid.run),
  Command("export-skills", "cron job: export the skills of Hermes to piabrota/skills in a PR", ExportSkills.run),
  Command("omp-run", "run one omp task through omp-stream, or stop one (hermes-omp skill)", OmpRun.run),
  Command("omp-stream", "turn the JSON lines of `omp --mode json` into plain lines (hermes-omp skill)", OmpStream.run),
  Command("kvm4-health", "the health of the box and of the Hermes units (kvm4-health skill)", Kvm4Health.run),
  Command("manim-smoke", "render the hermes-manim skill's smoke scene and check the video", ManimSmoke.run),
)
