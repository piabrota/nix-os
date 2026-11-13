#!/usr/bin/env python3
"""Tests of the logic of the openrig-wf-keeper script (openrig.nix) against a fake `rig`.

  python3 scripts/wf_keeper_test.py /nix/store/...-openrig-wf-keeper/bin/openrig-wf-keeper

`jq` must be on PATH. The script's own PATH line is removed, so the fake `rig` wins.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

FAKE_RIG = r"""#!/bin/sh
case "$*" in
  status) cat "$FAKE/status"; exit 0 ;;
  "ps --json") cat "$FAKE/ps.json" ;;
  "ps --nodes --rig wave-forecaster-dev --json") cat "$FAKE/nodes.json" ;;
  "up wave-forecaster-dev --existing") echo existing >>"$FAKE/calls"; exit "$(cat "$FAKE/existing.rc")" ;;
  "up /etc/openrig/specs/rigs/wave-forecaster-dev/rig.yaml") echo spec >>"$FAKE/calls"; exit "$(cat "$FAKE/spec.rc")" ;;
  *) echo "fake rig: unexpected call: $*" >&2; exit 99 ;;
esac
"""


def port(status, attention, running):
    rig = {"name": "wave-forecaster-dev", "status": status, "attentionCount": attention}
    return json.dumps([{**rig, "isArchived": False, "runningCount": running}])


STOPPED_NODES = json.dumps(
    [
        {"logicalId": "port.porter", "lifecycleState": "stopped", "intentionallyStopped": False},
        {"logicalId": "port.auditor", "lifecycleState": "stopped"},
    ]
)


class Keeper:
    def __init__(self, keeper, tmp):
        self.tmp = tmp
        (tmp / "bin").mkdir()
        (tmp / "state").mkdir()
        self.keeper = tmp / "keeper"
        lines = Path(keeper).read_text().splitlines(keepends=True)
        self.keeper.write_text("".join(x for x in lines if not x.startswith("export PATH=")))
        self.keeper.chmod(0o755)
        (tmp / "bin/rig").write_text(FAKE_RIG)
        (tmp / "bin/rig").chmod(0o755)
        self.fake = tmp / "fake"
        self.attempts = tmp / "state/attempts"
        self.env = {
            **os.environ,
            "FAKE": str(self.fake),
            "STATE_DIRECTORY": str(tmp / "state"),
            "PATH": f"{tmp / 'bin'}:{os.environ['PATH']}",
        }

    def run(self, rigs, nodes, existing_rc, spec_rc, attempts=None, daemon=True):
        self.fake.mkdir(exist_ok=True)
        (self.fake / "calls").write_text("")
        (self.fake / "status").write_text("Daemon running on port 7433\n" if daemon else "Daemon not running.\n")
        (self.fake / "ps.json").write_text(rigs)
        (self.fake / "nodes.json").write_text(nodes)
        (self.fake / "existing.rc").write_text(f"{existing_rc}\n")
        (self.fake / "spec.rc").write_text(f"{spec_rc}\n")
        if attempts is None:
            self.attempts.unlink(missing_ok=True)
        else:
            self.attempts.write_text(attempts)
        done = subprocess.run([str(self.keeper)], env=self.env, capture_output=True, text=True, check=False)
        calls = " ".join((self.fake / "calls").read_text().split())
        return done.returncode, calls, done.stdout + done.stderr


def main(keeper):
    now = int(time.time())
    old, recent = now - 7200, now - 600
    three = f"{recent}\n" * 3
    # name, rigs, nodes, existing rc, spec rc, attempts, exit, calls, a line of the output
    cases = [
        ("daemon down", "[]", "[]", 0, 0, None, 0, "", "daemon not running"),
        ("running", port("running", 0, 2), "[]", 0, 0, None, 0, "", "runs"),
        ("running, attention", port("running", 2, 2), "[]", 0, 0, None, 0, "", "<4>"),
        (
            "partial",
            port("partial", 0, 1),
            '[{"logicalId":"port.auditor","lifecycleState":"stopped"},{"logicalId":"port.porter","lifecycleState":"running"}]',
            0, 0, None, 0, "", "port.auditor=stopped",
        ),
        ("stopped, snapshot", port("stopped", 0, 0), STOPPED_NODES, 0, 1, None, 0, "existing", "restored"),
        ("stopped, existing fails", port("stopped", 0, 0), STOPPED_NODES, 1, 0, None, 0, "existing spec", "started from"),
        ("stopped, both fail", port("stopped", 0, 0), STOPPED_NODES, 1, 1, None, 1, "existing spec", "<3>"),
        (
            "stopped on purpose",
            port("stopped", 0, 0),
            '[{"logicalId":"a","intentionallyStopped":true},{"logicalId":"b","intentionallyStopped":true}]',
            0, 0, None, 0, "", "on purpose",
        ),
        ("no rig of that name", "[]", "[]", 1, 0, None, 0, "spec", "started from"),
        (
            "archived rig is ignored",
            '[{"name":"wave-forecaster-dev","status":"running","isArchived":true,"runningCount":2}]',
            "[]", 1, 0, None, 0, "spec", "started from",
        ),
        (
            "another rig runs",
            (
                '[{"name":"piabrota-dev","status":"running","isArchived":false,"runningCount":2},'
                '{"name":"wave-forecaster-dev","status":"stopped","isArchived":false,"runningCount":0}]'
            ),
            STOPPED_NODES, 0, 0, None, 0, "", "another rig runs: piabrota-dev, skipped",
        ),
        ("3 attempts in the last hour", port("stopped", 0, 0), STOPPED_NODES, 0, 0, three, 1, "", "<3>"),
        ("old attempts are dropped", port("stopped", 0, 0), STOPPED_NODES, 0, 0, f"{old}\n" * 3, 0, "existing", "restored"),
    ]  # fmt: skip
    with tempfile.TemporaryDirectory() as tmp:
        k = Keeper(keeper, Path(tmp))
        fails = 0
        for name, rigs, nodes, erc, src, att, want_exit, want_calls, want_out in cases:
            rc, calls, out = k.run(rigs, nodes, erc, src, att, daemon=name != "daemon down")
            if rc == want_exit and calls == want_calls and want_out in out:
                print(f"ok   {name}")
            else:
                print(f"FAIL {name}: exit {rc} (want {want_exit}), calls '{calls}' (want '{want_calls}'), output:")
                print("".join(f"     {line}\n" for line in out.splitlines()), end="")
                fails += 1
        # The attempts file keeps the recent lines and adds one; the old ones go.
        k.run(port("stopped", 0, 0), STOPPED_NODES, 0, 0, f"{old}\n{recent}\n")
        lines = k.attempts.read_text().split()
        if len(lines) == 2 and str(old) not in lines:
            print("ok   attempts file is trimmed and appended")
        else:
            print(f"FAIL attempts file: {' '.join(lines)}")
            fails += 1
    if fails:
        print(f"{fails} failed")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: wf_keeper_test.py <path of the keeper script>")
    sys.exit(main(sys.argv[1]))
