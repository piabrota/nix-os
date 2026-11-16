package piabrota.metrics

import piabrota.lib.Command

/** The commands of metrics/ (metrics.nix, docs/METRICS.md): the timers on the boxes, and the
  * preview of the page on a workstation.
  */
val commands: List[Command] = List(
  Command("metrics-collect", "one run of the collector: /proc and the cgroups into OUT_DIR/<name>.json", Collect.run),
  Command("metrics-probe", "one run of the probe: the sites' answers, their visits and the commit count", Probe.run),
  Command("metrics-export", "every host file as all.json and metrics.prom (Prometheus)", Export.run),
  Command("metrics-pull", "fetch another host's metrics file and keep it beside this host's", Pull.run),
  Command("metrics-preview", "serve metrics/index.html on a fixture case: [case] [port] | --check", Preview.run),
)
