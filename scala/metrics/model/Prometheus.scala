package piabrota.metrics

/** The Prometheus text format 0.0.4, as metrics.prom is written (docs/METRICS.md, "For machines"). */
enum MetricKind:
  case Gauge, Counter

  def render: String = toString.toLowerCase

/** The label names of metrics.prom. */
enum Label:
  case Host, Window, Cpu, Kind, Direction, State, Resource, Item, Version, Site, Repo, Unit

  def render: String = toString.toLowerCase

/** One sample: name, type, help, labels, value. */
final case class Metric(name: String, kind: MetricKind, help: String, labels: Seq[(Label, Json)], value: Json):
  /** `name{label="value",...} value`, a label cut to 128 characters and escaped. */
  def line: String =
    val ls = labels.map((k, v) => s"""${k.render}="${Metric.escape(v.tostring)}"""")
    name + (if ls.isEmpty then "" else ls.mkString("{", ",", "}")) + " " + value.tostring

object Metric:
  /** Every name starts with it. */
  val Prefix = "piabrota_"

  /** A sample, or nothing when the value is not a finite number. */
  def of(name: String, kind: MetricKind, help: String, labels: Seq[(Label, Json)], value: Json): Option[Metric] =
    Option.when(Json.finite(value))(Metric(Prefix + name, kind, help, labels, value))

  def escape(s: String): String =
    val cut = if s.codePointCount(0, s.length) <= 128 then s else s.substring(0, s.offsetByCodePoints(0, 128))
    cut.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

  /** Every sample, grouped by name in name order, each group under its HELP and TYPE lines. */
  def render(metrics: Vector[Metric]): String =
    metrics.groupBy(_.name).toVector.sortBy(_._1).map { (name, group) =>
      // groupBy keeps the order of each group's samples, as jq's group_by does.
      s"# HELP $name ${group.head.help}\n# TYPE $name ${group.head.kind.render}\n" + group.map(_.line).mkString("\n")
    }.mkString("\n")
