#!/usr/bin/env python3
"""Tests of metrics/collect.sh and metrics/probe.sh against a fixture tree for /proc,
/sys/fs/cgroup and /etc/passwd, and a fake curl. Prints "N checks, M failed"; exits 1 on a failure.

  python3 metrics/test/collect_test.py      (just metrics-test)

AWK may name another awk (for example mawk or busybox awk) to run the collector with. The
collector itself stays POSIX sh and awk: it runs on both boxes every 10 s.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
COLLECT = HERE.parent / "collect.sh"
PROBE = HERE.parent / "probe.sh"

FAKE_CURL = r"""#!/bin/sh
for a; do url=$a; done
echo "$url" >> "$FAKE_LOG"
case $url in
  */commits\?*) [ -n "$FAKE_LINK" ] || exit 7; printf 'HTTP/2 200\r\nlink: %s\r\n\r\n' "$FAKE_LINK" ;;
  https://up.example/) printf 200 ;;
  http://auth.example/) printf 401 ;;
  *) printf 000; exit 7 ;;
esac
"""


def canon(x):
    """Every number canonical, as `(.. | numbers) |= . + 0` makes it in jq: 30.0 is 30."""
    if isinstance(x, float) and x.is_integer():
        return int(x)
    if isinstance(x, dict):
        return {k: canon(v) for k, v in x.items()}
    if isinstance(x, list):
        return [canon(v) for v in x]
    return x


class Suite:
    def __init__(self, work):
        self.work = work
        self.proc, self.cg = work / "proc", work / "cg"
        self.out, self.st = work / "out", work / "st"
        self.out.mkdir()
        self.st.mkdir()
        (work / "passwd").write_text("root:x:0:0::/root:/bin/sh\nalice:x:1000:100::/home/alice:/bin/sh\n")
        self.checks = self.failed = 0
        self.opts = {}  # inventory, probe file, repo, profile, NixOS version
        self.cgroup_root = self.cg
        self.path = os.environ["PATH"]
        if os.environ.get("AWK"):
            (work / "bin").mkdir()
            (work / "bin/awk").symlink_to(shutil.which(os.environ["AWK"]))
            self.path = f"{work / 'bin'}:{self.path}"

    # -- the checks
    def check(self, desc, got, want):
        self.checks += 1
        if got != want:
            self.failed += 1
            print(f"FAIL {desc}: got [{got!r}], want [{want!r}]")

    def ok(self, desc, cond):
        self.check(desc, bool(cond), True)

    def data(self):
        return canon(json.loads((self.out / "piabrota2.json").read_text()))

    def valid(self):
        try:
            json.loads((self.out / "piabrota2.json").read_text())
            return True
        except ValueError:
            return False

    # -- the runs
    def run(self, script=COLLECT, **env):
        none = str(self.work / "none")
        e = {
            "PATH": self.path,
            "METRICS_NAME": "piabrota2",
            "METRICS_LABEL": "piabrota2 (KVM 4)",
            "OUT_DIR": str(self.out),
            "STATE_DIR": str(self.st),
            "METRICS_INVENTORY": self.opts.get("inv", ""),
            "METRICS_PROBE": self.opts.get("probe", ""),
            "METRICS_REPO": self.opts.get("repo", ""),
            "SYSTEM_PROFILE": self.opts.get("profile") or none,
            "NIXOS_VERSION_FILE": self.opts.get("nver") or none,
            "PROC_ROOT": str(self.proc),
            "CGROUP_ROOT": str(self.cgroup_root),
            "PASSWD_FILE": str(self.work / "passwd"),
            **env,
        }
        done = subprocess.run(["sh", str(script)], env=e, capture_output=True, text=True, check=False)
        self.err = done.stderr
        sys.stderr.write(done.stderr)
        return done.returncode == 0

    # -- the fixtures
    def proc_add(self, pid, comm, utime, stime, start, rss, uid, root=None):
        d = (root or self.proc) / str(pid)
        d.mkdir(parents=True, exist_ok=True)
        (d / "stat").write_text(
            f"{pid} ({comm}) S 1 {pid} {pid} 0 -1 4194560 100 0 0 0 {utime} {stime} 0 0 20 0 1 0 {start} 1000000 "
            f"{rss} 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 0 0 0 0 0 0\n"
        )
        (d / "statm").write_text(f"5000 {rss} 100 10 0 100 0\n")
        (d / "status").write_text(f"Name:\tx\nUid:\t{uid}\t{uid}\t{uid}\t{uid}\n")

    def sys_add(self, uptime, *cpu):
        """UPTIME, then user system idle iowait for all, cpu0 and cpu1 (nice is 0)."""
        self.proc.mkdir(exist_ok=True)
        (self.proc / "uptime").write_text(f"{uptime} 5000.00\n")
        (self.proc / "loadavg").write_text("0.50 0.25 0.10 1/100 999\n")
        (self.proc / "meminfo").write_text(
            "MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\n"
            "SwapTotal:       1000000 kB\nSwapFree:         400000 kB\n"
        )
        rows = [cpu[0:4], cpu[4:8], cpu[8:12]]
        text = "".join(f"{n} {u} 0 {s} {i} {w} 0 0 0 0 0\n" for n, (u, s, i, w) in zip(("cpu ", "cpu0", "cpu1"), rows))
        (self.proc / "stat").write_text(text + "intr 1\n")

    def io_add(self, ctxt, forks, rx, tx, sread, swrite):
        """The counters of one sample, after sys_add. The network is PID 1's; sda1 and lo do not count."""
        p = self.proc
        with (p / "stat").open("a") as f:
            f.write(f"ctxt {ctxt}\nprocesses {forks}\nprocs_running 3\nprocs_blocked 1\n")
        (p / "meminfo").write_text(
            "MemTotal:        8000000 kB\nMemFree:          100000 kB\nMemAvailable:    3000000 kB\n"
            "Buffers:           10000 kB\nCached:          2000000 kB\nSwapTotal:       1000000 kB\n"
            "SwapFree:         400000 kB\nShmem:             50000 kB\nDirty:               300 kB\n"
        )
        (p / "loadavg").write_text("0.50 0.25 0.10 2/345 999\n")
        for d in ("1/net", "pressure", "sys/fs"):
            (p / d).mkdir(parents=True, exist_ok=True)
        (p / "1/net/dev").write_text(
            "Inter-|   Receive                            |  Transmit\n"
            " face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n"
            "    lo: 99999 9 0 0 0 0 0 0 99999 9 0 0 0 0 0 0\n"
            f"  eth0: {rx} 10 0 0 0 0 0 0 {tx} 10 0 0 0 0 0 0\n"
        )
        (p / "1/net/sockstat").write_text(
            "sockets: used 40\nTCP: inuse 7 orphan 0 tw 3 alloc 9 mem 2\nUDP: inuse 4 mem 1\n"
        )
        (p / "diskstats").write_text(
            f"   8       0 sda 100 0 {sread} 50 200 0 {swrite} 60 0 70 110\n"
            f"   8       1 sda1 100 0 {sread} 50 200 0 {swrite} 60 0 70 110\n"
            "   7       0 loop0 1 0 999 1 0 0 999 0 0 1 1\n"
        )
        (p / "sys/fs/file-nr").write_text("1234\t0\t9223372036854775807\n")
        (p / "pressure/cpu").write_text(
            "some avg10=1.50 avg60=1.00 avg300=0.50 total=100\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n"
        )
        (p / "pressure/memory").write_text(
            "some avg10=0.25 avg60=0.10 avg300=0.00 total=10\nfull avg10=0.10 avg60=0.00 avg300=0.00 total=5\n"
        )
        (p / "pressure/io").write_text(
            "some avg10=4.00 avg60=2.00 avg300=1.00 total=900\nfull avg10=3.00 avg60=1.00 avg300=0.50 total=800\n"
        )

    def cg_add(self, unit, mx, cur, peak=None):
        d = self.cg / "system.slice" / unit
        d.mkdir(parents=True, exist_ok=True)
        (d / "memory.max").write_text(f"{mx}\n")
        (d / "memory.current").write_text(f"{cur}\n")
        if peak is not None:
            (d / "memory.peak").write_text(f"{peak}\n")


LATER = (1500, 600, 9300, 600, 800, 300, 4600, 300, 700, 300, 4700, 300)
HOSTILE = 'a"b\\c</scr<img>'


def main():
    if os.sysconf("SC_CLK_TCK") != 100 or os.sysconf("SC_PAGE_SIZE") != 4096:
        print("the fixtures assume CLK_TCK 100 and a 4096 byte page", file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory() as tmp:
        t = Suite(Path(tmp))
        try:
            scenario(t)
        finally:
            for root, dirs, _ in os.walk(tmp):
                for d in dirs:
                    os.chmod(os.path.join(root, d), 0o755)
    print(f"{t.checks} checks, {t.failed} failed")
    return int(t.failed > 0)


def scenario(t):
    """One story, in order, as the box lives it."""
    # Sample 1, at uptime 1000 s. cpu0 and cpu1 each: 500/250 user/system, 4000 idle, 250 iowait.
    t.sys_add("1000.00", 1000, 500, 8000, 500, 500, 250, 4000, 250, 500, 250, 4000, 250)
    t.io_add(10000, 500, 1000000, 500000, 2000, 4000)
    t.proc_add(100, "alpha", 100, 50, 10, 1000, 1000)
    t.proc_add(200, "my proc (x)", 10, 0, 20, 3000, 0)
    t.proc_add(300, HOSTILE, 5, 0, 30, 500, 4242)
    t.proc_add(500, "nl\nx", 1, 0, 40, 100, 1000)
    (t.proc / "400").mkdir()  # a process that ended while it was read: no files
    (t.proc / "600").mkdir()
    (t.proc / "600/stat").write_text("")  # an empty stat
    (t.proc / "self").mkdir()
    (t.proc / "sys").mkdir(exist_ok=True)  # not processes
    t.cg_add("a.service", 1000, 500, 700)
    t.cg_add("b.service", "max", 900)
    t.cg_add("c.service", 2000, 1900)
    (t.cg / "system.slice/d.service").mkdir()  # no memory.max at all
    (t.cg / "system.slice/sub.slice").mkdir()  # not a service

    print("# first run: nothing to compare with")
    t.ok("first run exits 0", t.run())
    t.ok("first run is valid JSON", t.valid())
    d = t.data()
    t.check("first run warming", d["cpu"].get("warming"), True)
    t.check("first run cpu is 0", [d["cpu"]["total_pct"], d["cpu"]["cores"][0]], [0, 0])
    t.check("first run process cpu is 0", sum(p["cpu_pct"] for p in d["top_cpu"]), 0)
    rates = [d["tasks"]["forks_per_s"], d["tasks"]["ctxt_per_s"], d["net"]["rx_bps"], d["net"]["tx_bps"]]
    rates += [d["disk_io"]["read_bps"], d["disk_io"]["write_bps"]]
    t.check("first run rates are 0", rates, [0] * 6)
    t.ok("state file written", (t.st / "piabrota2.state").stat().st_size > 0)
    t.check("no temp file left", [p for p in [*t.out.rglob("*.tmp"), *t.st.rglob("*.tmp")]], [])
    t.check("file mode is 0644", stat.S_IMODE((t.out / "piabrota2.json").stat().st_mode), 0o644)

    print("# second run, 10 s later")
    t.sys_add("1010.00", *LATER)
    t.io_add(15000, 520, 2000000, 600000, 2200, 6000)
    t.proc_add(100, "alpha", 200, 100, 10, 1000, 1000)
    t.proc_add(200, "my proc (x)", 310, 0, 20, 3000, 0)
    t.proc_add(300, HOSTILE, 5, 0, 30, 500, 4242)
    t.proc_add(500, "nl\nx", 1, 0, 40, 100, 1000)
    t.proc_add(700, "newbie", 50, 0, 100550, 50, 1000)  # started at 1005.5 s, inside the window
    t.cg_add("c.service", 2000, 1950, 1990)
    t.ok("second run exits 0", t.run())
    t.ok("second run is valid JSON", t.valid())
    d = t.data()
    t.check("schema version", d["v"], 1)
    t.check("host", d["host"], "piabrota2")
    t.check("label", d["label"], "piabrota2 (KVM 4)")
    t.check("interval", d["interval"], 10)
    t.check("ts is a recent unix time", d["ts"] > 1700000000, True)
    t.check("uptime", d["uptime_s"], 1010)
    t.check("vcpus", d["vcpus"], 2)
    t.check("load", d["load"], [0.5, 0.25, 0.1])
    t.check("warming is gone", "warming" in d["cpu"], False)
    t.check("cpu total", d["cpu"]["total_pct"], 30)
    t.check("cpu cores", d["cpu"]["cores"], [35, 25])
    t.check("mem total", d["mem"]["total"], 8192000000)
    t.check("mem used is total minus available", d["mem"]["used"], 5120000000)
    t.check("mem available", d["mem"]["available"], 3072000000)
    t.check("swap", [d["mem"]["swap_total"], d["mem"]["swap_used"]], [1024000000, 614400000])
    t.check("disk is numbers", d["disk"]["root_total"] > 0 and d["disk"]["root_used"] > 0, True)
    t.check(
        "mem detail", d["mem_detail"], {"buffers": 10240000, "cached": 2048000000, "shmem": 51200000, "dirty": 307200}
    )
    t.check("tasks", d["tasks"], {"threads": 345, "running": 3, "blocked": 1, "forks_per_s": 2, "ctxt_per_s": 500})
    t.check("open files", d["fds_open"], 1234)
    t.check(
        "network of PID 1, without lo",
        d["net"],
        {"rx_bps": 100000, "tx_bps": 10000, "rx_total": 2000000, "tx_total": 600000},
    )
    t.check("sockets", d["sockets"], {"tcp": 7, "tcp_tw": 3, "udp": 4})
    t.check(
        "disk io of whole disks only",
        d["disk_io"],
        {"read_bps": 10240, "write_bps": 102400, "read_total": 1126400, "write_total": 3072000},
    )
    t.check(
        "pressure",
        d["pressure"],
        {"cpu": {"some": 1.5, "full": 0}, "memory": {"some": 0.25, "full": 0.1}, "io": {"some": 4, "full": 3}},
    )
    t.check("procs_total skips the ones that ended", d["procs_total"], 5)
    t.check("top_mem order", [p["pid"] for p in d["top_mem"]], [200, 100, 300, 500, 700])
    t.check("top_cpu order, ties by pid", [p["pid"] for p in d["top_cpu"]], [200, 100, 700, 300, 500])
    t.check("cpu of a process", [d["top_cpu"][0]["cpu_pct"], d["top_cpu"][1]["cpu_pct"]], [30, 15])
    t.check("cpu of a process that started in the window", d["top_cpu"][2]["cpu_pct"], 5)
    t.check("rss in bytes", d["top_mem"][0]["rss"], 12288000)
    t.check("user from passwd", [d["top_mem"][0]["user"], d["top_mem"][1]["user"]], ["root", "alice"])
    t.check("unknown uid stays a number", d["top_mem"][2]["user"], "4242")
    t.check("name with spaces and a parenthesis", d["top_mem"][0]["name"], "my proc (x)")
    t.check("hostile name round-trips", d["top_mem"][2]["name"], HOSTILE)
    t.check("newline in a name becomes ?", d["top_mem"][3]["name"], "nl?x")
    t.check("units sorted by share of the limit", [u["unit"] for u in d["units"]], ["c.service", "a.service"])
    t.check("unit numbers with a peak", d["units"][1], {"unit": "a.service", "mem": 500, "max": 1000, "peak": 700})
    t.check("unit numbers", d["units"][0], {"unit": "c.service", "mem": 1950, "max": 2000, "peak": 1990})
    raw = (t.out / "piabrota2.json").read_text()
    t.check("the file stays under 8 KB", len(raw.encode()) < 8192, True)
    t.check("no command line in the file", "/bin/" in raw or "cmdline" in raw, False)
    t.check("services running: every unit with a cgroup", d["services_running"], 4)
    t.check("no inventory without the file", "inventory" in d, False)

    print("# the inventory")
    inv = t.work / "inventory"
    t.opts["inv"] = str(inv)
    # Lines the collector must drop: a quote, a capital, a negative, a fraction, three fields, a key
    # that is too long, a number that is too long, a repeated key, an empty line.
    inv.write_text(
        "apps 1\nsites 7\nskills 120\n"
        f'x"y 1\nApps 2\nrigs -1\nmcp 1.5\nplugins 1 2\n{"a" * 25} 1\ntimers 1234567890\napps 9\n\n'
    )
    t.ok("run with an inventory", t.run())
    t.ok("the inventory run is valid JSON", t.valid())
    t.check("inventory keeps the good lines, in order", t.data()["inventory"], {"apps": 1, "sites": 7, "skills": 120})
    inv.write_text("".join(f"k{str(i).translate(str.maketrans('0123456789', 'abcdefghij'))} 1\n" for i in range(30)))
    t.ok("run with a long inventory", t.run())
    t.check("24 inventory keys at most", len(t.data()["inventory"]), 24)
    inv.write_text("")
    t.ok("run with an empty inventory", t.run())
    t.check("an empty inventory is an empty object", t.data()["inventory"], {})
    t.opts["inv"] = str(t.work / "nope")
    t.ok("run with an inventory file that is missing", t.run())
    t.check("a missing inventory file is an empty object", t.data()["inventory"], {})
    t.opts.clear()

    print("# the system, the probe file and the repository")
    d = t.data()
    t.check("an empty system without its files", d["system"], {})
    t.check("no domains and no repo without a probe file", "domains" in d or "repo" in d, False)
    (t.work / "system").symlink_to("system-42-link")
    (t.work / "nixos-version").write_text("26.05.20261101.abcdef0")
    probef = t.work / "probe"
    t.opts.update(
        profile=str(t.work / "system"), nver=str(t.work / "nixos-version"), probe=str(probef), repo="piabrota/nix-os"
    )
    # Lines the collector must drop: a capital and a quote in a name, a code of 4 digits, a count
    # that is not a number.
    probef.write_text(
        "ts 1700000000\ndomain www.piabrota.art 200\ndomain metrics.piabrota.art 401\n"
        'domain down.piabrota.art 000\ndomain bad.piabrota.art 502\ndomain B"x 200\ndomain long 2000\n'
        "repo 230 1699999000\nrepo x 1\n"
    )
    t.ok("run with a probe file", t.run())
    t.ok("the probe run is valid JSON", t.valid())
    d = t.data()
    t.check("the version and the generation", d["system"], {"nixos": "26.05.20261101.abcdef0", "generation": 42})
    t.check(
        "an answer below 500 is up",
        [[x["name"], x["code"], x["up"]] for x in d["domains"]["list"]],
        [
            ["www.piabrota.art", 200, True],
            ["metrics.piabrota.art", 401, True],
            ["down.piabrota.art", 0, False],
            ["bad.piabrota.art", 502, False],
        ],
    )
    t.check("the counts of the sites", [d["domains"][k] for k in ("ts", "up", "total")], [1700000000, 2, 4])
    t.check("the repository", d["repo"], {"name": "piabrota/nix-os", "commits": 230, "ts": 1699999000})
    (t.work / "nixos-version").write_text('not a "version"')
    (t.work / "system").unlink()
    (t.work / "system").symlink_to("system-x-link")
    probef.write_text("".join(f"domain d{i}.example 200\n" for i in range(30)) + "ts 1700000000\n")
    t.ok("run with bad system files and many sites", t.run())
    d = t.data()
    t.check("a bad version and a bad generation are left out", d["system"], {})
    t.check("24 sites at most", d["domains"]["total"], 24)
    t.check("no repo without its line", "repo" in d, False)
    t.opts["probe"] = str(t.work / "nope")
    t.ok("run with a probe file that is missing", t.run())
    t.check("a missing probe file gives no domains", "domains" in t.data(), False)
    t.opts.clear()

    probe_suite(t)

    print("# the caps")
    for i in range(1000, 1030):
        t.proc_add(i, f"p{i}", 1, 0, 50, i - 900, 1000)
        t.cg_add(f"u{i}.service", 100, i - 900)
    t.sys_add("1020.00", *LATER)
    t.ok("run with many processes", t.run())
    d = t.data()
    t.check("10 processes in each list", [len(d["top_mem"]), len(d["top_cpu"])], [10, 10])
    t.check("12 units at most", len(d["units"]), 12)
    t.check("the cap run is under 8 KB", (t.out / "piabrota2.json").stat().st_size < 8192, True)
    for i in range(1000, 1030):
        shutil.rmtree(t.proc / str(i))
        shutil.rmtree(t.cg / f"system.slice/u{i}.service")

    print("# a process that cannot be read, and a missing cgroup tree")
    if os.getuid() != 0:
        t.proc_add(800, "locked", 1, 0, 60, 100, 1000)
        (t.proc / "800/stat").chmod(0)
        t.sys_add("1030.00", *LATER)
        t.ok("run with an unreadable stat", t.run())
        t.check("the unreadable process is skipped", 800 in [p["pid"] for p in t.data()["top_mem"]], False)
        t.check("and nothing on stderr", t.err, "")
        (t.proc / "800/stat").chmod(0o644)
        shutil.rmtree(t.proc / "800")
    t.sys_add("1040.00", *LATER)
    t.cgroup_root = t.work / "none"
    t.ok("run with no cgroup tree", t.run())
    t.check("units is empty", t.data()["units"], [])
    t.ok("still valid JSON", t.valid())
    t.check("nothing on stderr", t.err, "")

    print("# a clock that went back or a garbled state counts as a first run")
    (t.st / "piabrota2.state").write_text("garbage\nT notanumber\n")
    t.ok("run with a garbled state", t.run())
    t.ok("valid JSON", t.valid())
    t.sys_add("10.00", *LATER)
    (t.st / "piabrota2.state").write_text("T 5000\n")
    t.ok("run after a reboot", t.run())
    t.check("warming after a reboot", t.data()["cpu"].get("warming"), True)

    print("# the escaper: a naive one breaks the JSON, so these checks can fail")
    naive = t.work / "naive.sh"
    naive.write_text(COLLECT.read_text().replace('c == "\\\\" || ', ""))
    t.check("the mutation changed the script", naive.read_text() != COLLECT.read_text(), True)
    t.sys_add("1050.00", *LATER)
    t.run(naive)
    t.check("a naive escaper makes invalid JSON", t.valid(), False)
    t.run()
    t.check("the real escaper makes valid JSON", t.valid(), True)

    print("# a bad name is refused")
    done = subprocess.run(
        ["sh", str(COLLECT)],
        env={"PATH": t.path, "METRICS_NAME": "../x", "OUT_DIR": str(t.out), "STATE_DIR": str(t.st)},
        capture_output=True,
        check=False,
    )
    t.check("bad METRICS_NAME exits 2", done.returncode, 2)


def probe_suite(t):
    print("# the probe")
    pst, fake, log = t.work / "pst", t.work / "fake", t.work / "curl.log"
    fake.mkdir()
    (fake / "curl").write_text(FAKE_CURL)
    (fake / "curl").chmod(0o755)
    sites = t.work / "sites"
    sites.write_text(
        "up.example https://up.example/\nauth.example http://auth.example/\ndown.example https://down.example/\n"
        "Bad.example https://x/\nno-url.example ftp://x/\n"
    )
    log.write_text("")

    def probe_run(link, every="600"):
        env = {
            "PATH": f"{fake}:{t.path}",
            "FAKE_LOG": str(log),
            "FAKE_LINK": link,
            "METRICS_NAME": "piabrota2",
            "STATE_DIR": str(pst),
            "PROBE_SITES": str(sites),
            "PROBE_REPO": "piabrota/nix-os",
            "GITHUB_API": "https://api.test",
            "PROBE_REPO_EVERY": every,
        }
        done = subprocess.run(["sh", str(PROBE)], env=env, capture_output=True, text=True, check=False)
        t.err = done.stderr
        return done.returncode == 0

    def pline(key):
        return [
            line.split(" ", 1)[1]
            for line in (pst / "piabrota2.probe").read_text().splitlines()
            if line.startswith(f"{key} ")
        ]

    last = '<https://api.test/repositories/1/commits?per_page=1&sha=main&page=2>; rel="next", '
    last += '<https://api.test/repositories/1/commits?per_page=1&sha=main&page=230>; rel="last"'
    t.ok("the probe runs", probe_run(last))
    t.check(
        "a code for each good site, 000 when nothing answers",
        pline("domain"),
        ["up.example 200", "auth.example 401", "down.example 000"],
    )
    t.check("the count is the last page", pline("repo")[0].split()[0], "230")
    asked = [
        u
        for u in log.read_text().splitlines()
        if u.endswith("api.test/repos/piabrota/nix-os/commits?per_page=1&sha=main")
    ]
    t.check("GitHub is asked for one commit a page", len(asked), 1)
    t.ok("a second run", probe_run('<https://api.test/x?page=999>; rel="last"'))
    t.check("GitHub is not asked again within PROBE_REPO_EVERY", log.read_text().count("api.test"), 1)
    t.check("and the count stays", pline("repo")[0].split()[0], "230")
    probe_run("", every="0")
    t.check("a GitHub that does not answer keeps the old count", pline("repo")[0].split()[0], "230")
    t.check("and the time it was asked", len(pline("asked")), 1)
    probe_run('<https://api.test/x?page=999>; rel="last"', every="0")
    t.check("a new count when it answers", pline("repo")[0].split()[0], "999")
    t.check("nothing on stderr", t.err, "")
    t.check("the probe file is not in the served folder", list(t.out.rglob("*probe*")), [])
    t.opts.update(probe=str(pst / "piabrota2.probe"), repo="piabrota/nix-os")
    t.ok("the collector reads the probe file", t.run())
    d = t.data()
    t.check(
        "the collector shows what the probe found",
        [d["domains"]["up"], d["domains"]["total"], d["repo"]["commits"]],
        [2, 3, 999],
    )
    t.opts.clear()
    done = subprocess.run(
        ["sh", str(PROBE)],
        env={"PATH": t.path, "METRICS_NAME": "../x", "STATE_DIR": str(pst)},
        capture_output=True,
        check=False,
    )
    t.check("bad METRICS_NAME exits 2 in the probe", done.returncode, 2)


if __name__ == "__main__":
    sys.exit(main())
