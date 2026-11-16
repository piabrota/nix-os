package piabrota.scripts

import piabrota.lib.TestKit

/** restart-services with stub systemctl, tmux, nginx, rig, id and journalctl and a fixture /proc.
  * No stub is a real unit: nothing here restarts anything.
  */
class RestartServicesTest extends munit.FunSuite:
  // STUB_UNITS are the units that exist; STUB_LIST is what `list-units 'loco-*'` prints;
  // STUB_FAIL_UNIT is `failed`; STUB_SLOW=N makes hermes-agent say `activating` N times first.
  // Oneshot services are `inactive` after their run, as systemd reports a finished oneshot.
  // `cat` prints a secret, as a unit with Environment= could: the command must never show it.
  private val systemctl = """#!/bin/sh
echo "systemctl $*" >>"$LOG"
case $1 in
  cat)
    case " $STUB_UNITS " in *" $2 "*) echo "Environment=UNIT_SECRET=hunter2"; exit 0 ;; esac
    exit 1 ;;
  is-active)
    if [ "$2" = "${STUB_FAIL_UNIT:-}" ]; then echo failed; exit 3; fi
    if [ "$2" = hermes-agent.service ] && [ -n "${STUB_SLOW:-}" ]; then
      n=$(cat "$STUB_STATE/n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" >"$STUB_STATE/n"
      if [ "$n" -le "$STUB_SLOW" ]; then echo activating; exit 3; fi
    fi
    case $2 in metrics-*.service) echo inactive; exit 3 ;; esac
    echo active ;;
  show)
    case $3 in NRestarts) echo 0 ;; ActiveEnterTimestamp) echo "Sat 2026-11-07 10:00:00 UTC" ;; esac ;;
  list-units) printf '%s\n' "$STUB_LIST" ;;
esac
exit 0
"""
  private def logging(name: String) = s"#!/bin/sh\necho \"$name $$*\" >>\"$$LOG\"\necho SECRET-JOURNAL-LINE\n"
  private val fakes = TestKit.fakes(
    "systemctl" -> systemctl,
    "tmux" -> "#!/bin/sh\necho \"tmux $*\" >>\"$LOG\"\nprintf 'seat-a: 1 windows\\nseat-b: 1 windows\\n'\n",
    "id" -> "#!/bin/sh\necho \"${STUB_UID:-0}\"\n",
    "nginx" -> logging("nginx"), "rig" -> logging("rig"), "journalctl" -> logging("journalctl"),
  )

  private val work = os.temp.dir(prefix = "restart")
  private val log = work / "calls.log"
  private val state = work / "state"
  os.makeDir(state)

  /** A fixture /proc entry: its cgroup and its argv. */
  private def mkproc(dir: os.Path, pid: Int, cgroup: String, argv: String*): Unit =
    os.write.over(dir / pid.toString / "cgroup", cgroup + "\n", createFolders = true)
    os.write.over(dir / pid.toString / "cmdline", argv.map(_ + "\u0000").mkString)

  // ok: the wrapper and the gateway of the unit, and a decoy: an ssh session's `sh -c` whose single
  // argument holds the words (not a gateway). stray: a gateway of the dashboard's cgroup.
  private val unitCg = "0::/system.slice/hermes-agent.service"
  private val procOk = work / "proc-ok"
  mkproc(procOk, 100, unitCg, "sh", "/nix/store/x-hermes-gateway", "/nix/store/x/bin/hermes", "gateway", "run", "--external-supervisor")
  mkproc(procOk, 101, unitCg, "/nix/store/x/bin/python", "hermes", "gateway", "run", "--external-supervisor")
  mkproc(procOk, 300, "0::/user.slice/session-4.scope", "sudo", "sh", "-c", "echo gateway run\nrestart", "restart-services", "hermes")
  private val procStray = work / "proc-stray"
  os.copy(procOk, procStray)
  mkproc(procStray, 200, "0::/system.slice/hermes-backend.service", "/nix/store/x/bin/hermes", "gateway", "run")
  private val procNone = work / "proc-none"
  os.makeDir(procNone)

  os.write(work / "tty-y", "y\n")
  os.write(work / "tty-n", "n\n")
  private val openrigRun = work / "run-openrig"
  os.write(openrigRun / "tmux-999" / "default", "", createFolders = true)

  private val box2 = "metrics-collect.timer metrics-pull.timer metrics-collect.service metrics-pull.service nginx.service pgx.service room-listeners.service openrig.service hermes-agent.service hermes-backend.service loco-notes.service loco-notes-backup.service sshd.service loco-evil;rm.service systemd-networkd.service acme-www.service"
  private val box1 = "metrics-collect.timer metrics-collect.service nginx.service sshd.service"
  private val list = """loco-notes.service loaded active running Loco app notes
loco-notes-backup.service loaded inactive dead Back up notes
sshd.service loaded active running OpenSSH
loco-evil;rm.service loaded active running evil
systemd-networkd.service loaded active running net"""

  final case class Run(out: String, status: Int, changes: String, calls: List[String]):
    def has(s: String): Boolean = out.contains(s)

  private def run(args: String*)(env: (String, String)*): Run =
    os.write.over(log, "")
    os.remove(state / "n")
    val base = Map(
      "LOG" -> log.toString, "STUB_UNITS" -> box2, "STUB_LIST" -> list, "STUB_STATE" -> state.toString,
      "RESTART_PROC" -> procOk.toString, "RESTART_TTY" -> (work / "tty-y").toString,
      "RESTART_TMUX_DIR" -> (work / "none").toString, "RESTART_WAIT_STEP" -> "0", "RESTART_WAIT_TRIES" -> "5",
      "RESTART_SECRET" -> "hunter2")
    val r = TestKit.piabrota("restart-services" +: args, env = base ++ env, fakes = Some(fakes))
    val calls = os.read.lines(log).toList
    val changes = calls.filter(l => "^systemctl (restart|reload|start) .*".r.matches(l)).map(_.stripPrefix("systemctl ")).mkString("\n")
    Run(r.out.text() + r.err.text(), r.exitCode, changes, calls)

  private val missingTty = "RESTART_TTY" -> (work / "missing").toString

  test("list and --dry-run change nothing, ask nothing and need no root and no terminal"):
    val l = run("list")(missingTty, "STUB_UID" -> "1000")
    assertEquals(l.changes, "")
    assertEquals(l.status, 0)
    assert(l.has("restart  hermes-agent.service"), l.out)
    assert(l.has("ends running agent tasks"), l.out)
    assert(l.has("reload   nginx.service"), l.out)
    val d = run("all", "--dry-run")(missingTty, "STUB_UID" -> "1000")
    assertEquals(d.changes, "")
    assertEquals(d.status, 0)
    assert(d.has("systemctl restart hermes-agent.service"), d.out)
    assert(d.has("systemctl reload nginx.service"), d.out)
    assert(!d.has("Proceed?"), d.out)

  test("hermes: the agent first, the dashboard only after the agent is active"):
    val r = run("hermes")("STUB_SLOW" -> "2")
    assertEquals(r.changes, "restart hermes-agent.service\nrestart hermes-backend.service")
    val polls = r.calls.takeWhile(!_.startsWith("systemctl restart hermes-backend"))
      .count(_.startsWith("systemctl is-active hermes-agent.service"))
    assertEquals(polls, 3)
    assertEquals(r.status, 0, r.out)
    assert(r.has("ok    gateway: 2 process(es)"), r.out)
    assert(!r.has("WARN"), r.out)
    assert(r.has("NRestarts"), r.out)

  test("a stray gateway is named, with its cgroup and the fix"):
    val r = run("hermes")("RESTART_PROC" -> procStray.toString)
    val warns = r.out.linesIterator.filter(_.startsWith("WARN")).toList
    assertEquals(warns, List("WARN stray gateway pid 200 in /system.slice/hermes-backend.service: run: sudo systemctl restart hermes-backend"))
    assertEquals(r.status, 1)

  test("no gateway: WARN"):
    assert(run("hermes")("RESTART_PROC" -> procNone.toString).has("WARN no gateway process found"))

  test("agent never active: the dashboard is not touched"):
    val r = run("hermes")("STUB_SLOW" -> "999")
    assertEquals(r.changes, "restart hermes-agent.service")
    assertEquals(r.status, 1)

  test("rig: the live seats are counted from tmux, read-only; rig itself is never called"):
    val r = run("rig")("RESTART_TMUX_DIR" -> openrigRun.toString)
    assertEquals(r.changes, "restart openrig.service")
    assert(r.has("2 live tmux session(s) of OpenRig: they end with this restart"), r.out)
    assert(!r.calls.exists(_.startsWith("rig ")))
    assert(!run("rig")().has("live tmux"))

  test("metrics, web, pgx, room"):
    val m = run("metrics")()
    assertEquals(m.changes, "restart metrics-collect.timer\nrestart metrics-pull.timer\nstart metrics-collect.service\nstart metrics-pull.service")
    assertEquals(m.status, 0, m.out)
    val w = run("web")()
    assertEquals(w.changes, "reload nginx.service")
    assert(!w.calls.exists(_.startsWith("nginx ")))
    assertEquals(run("pgx")().changes, "restart pgx.service")
    assertEquals(run("room")().changes, "restart room-listeners.service")

  test("all: this order, and no unit outside the allow list"):
    val r = run("all")()
    assertEquals(r.changes, List("restart metrics-collect.timer", "restart metrics-pull.timer",
      "start metrics-collect.service", "start metrics-pull.service", "reload nginx.service",
      "restart pgx.service", "restart room-listeners.service", "restart loco-notes.service",
      "restart openrig.service", "restart hermes-agent.service", "restart hermes-backend.service").mkString("\n"))
    assertEquals(r.status, 0, r.out)
    assertEquals(r.out.linesIterator.count(l => "^[a-z-]+\\.(service|timer) +(active|inactive) +0 .*".r.matches(l)), 11, r.out)
    assertEquals(run("loco")().changes, "restart loco-notes.service")

  test("a box like piabrota (KVM 1): the groups it lacks are skipped, not an error"):
    val r = run("all")("STUB_UNITS" -> box1)
    assertEquals(r.changes, "restart metrics-collect.timer\nstart metrics-collect.service\nreload nginx.service")
    assertEquals(r.out.linesIterator.count(l => "^skip: .*: not on this box$".r.matches(l)), 5, r.out)
    assertEquals(r.status, 0)
    val h = run("hermes")("STUB_UNITS" -> box1)
    assert(h.has("skip: hermes: not on this box"))
    assertEquals((h.changes, h.status), ("", 0))

  test("the prompt reads the terminal, not stdin"):
    val y = run("web")()
    assertEquals(y.changes, "reload nginx.service")
    assert(y.has("Proceed? [y/N]"))
    val n = run("all")("RESTART_TTY" -> (work / "tty-n").toString)
    assertEquals((n.changes, n.status), ("", 2))
    val none = run("web")(missingTty)
    assertEquals((none.changes, none.status), ("", 2))
    assert(none.has("no terminal to ask on and no --yes"))
    val yes = run("web", "--yes")(missingTty)
    assertEquals((yes.changes, yes.has("Proceed?")), ("reload nginx.service", false))
    val user = run("web", "--yes")("STUB_UID" -> "1000")
    assertEquals((user.changes, user.status), ("", 2))

  test("a unit that stays failed gives exit 1, names the unit and the journal command"):
    val r = run("pgx")("STUB_FAIL_UNIT" -> "pgx.service")
    assertEquals(r.status, 1)
    assert(r.has("FAIL pgx.service is not as wanted: read: journalctl -u pgx.service -n 50"), r.out)
    assert(!r.calls.exists(_.startsWith("journalctl ")))

  test("usage errors change nothing"):
    for args <- List(Seq("nonsense"), Seq("web", "pgx"), Seq("web", "--force")) do
      val r = run(args*)()
      assertEquals((r.status, r.changes), (2, ""), args.toString)

  test("no secret and no journal text, whatever happened"):
    val r = run("all")("RESTART_TMUX_DIR" -> openrigRun.toString)
    for s <- List("hunter2", "UNIT_SECRET", "SECRET-JOURNAL", "PATH=") do assert(!r.has(s), s)
