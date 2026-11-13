#!/usr/bin/env python3
"""Tests of metrics/export.sh and metrics/export.jq on the page's fixtures (healthy, stale, missing, hostile).

python3 metrics/test/export_test.py      (just metrics-test)
"""

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPORT = HERE.parent / "export.sh"
FIXTURES = HERE / "fixtures"
# A sample line of the text format 0.0.4: a name, optional labels, a number.
SAMPLE = re.compile(r'[a-z_][a-z0-9_]*(\{([a-z_]+="([^"\\\n]|\\["\\n])*",?)*\})? -?[0-9][0-9.e+-]*')


# The fixtures' ts are seconds before now, as preview.py serves them: run() adds BASE.
BASE = 1800000000


def run(case, offset=0, extra=None):
    work = Path(tempfile.mkdtemp())
    shutil.copytree(FIXTURES / case / "data", work, dirs_exist_ok=True)
    for f in work.glob("*.json"):
        d = json.loads(f.read_text())
        if isinstance(d.get("ts"), int):
            d["ts"] += BASE
        f.write_text(json.dumps(d))
    now = BASE + offset
    for name, text in (extra or {}).items():
        (work / name).write_text(text)
    env = {**os.environ, "OUT_DIR": str(work), "METRICS_NOW": str(now)}
    subprocess.run(["sh", str(EXPORT)], env=env, check=True)

    def strict(c):
        raise ValueError(f"not JSON: {c}")

    doc = json.loads((work / "all.json").read_text(), parse_constant=strict)
    return work, doc, (work / "metrics.prom").read_text()


class Export(unittest.TestCase):
    def check_format(self, prom):
        names = set()
        for line in prom.splitlines():
            if line.startswith("# TYPE "):
                name = line.split()[2]
                self.assertNotIn(name, names, "one TYPE line for each name")
                names.add(name)
            elif not line.startswith("# HELP "):
                self.assertRegex(line, SAMPLE)
                self.assertIn(re.split(r"[{ ]", line)[0], names, "a sample after its TYPE")

    def test_healthy(self):
        work, doc, prom = run("healthy")
        self.assertEqual(sorted(doc["hosts"]), ["piabrota", "piabrota2"])
        self.assertTrue(doc["hosts"]["piabrota2"]["fresh"])
        self.assertEqual(doc["hosts"]["piabrota2"]["data"], json.loads((work / "piabrota2.json").read_text()))
        self.check_format(prom)
        self.assertIn('piabrota_host_fresh{host="piabrota2"} 1', prom)
        self.assertIn("piabrota_hosts 2", prom)
        self.assertRegex(prom, r'piabrota_memory_bytes\{host="piabrota2",kind="total"\} \d+')
        self.assertRegex(prom, r'piabrota_inventory\{host="piabrota2",item="packages"\} \d+')
        self.assertEqual(oct((work / "metrics.prom").stat().st_mode & 0o777), "0o644")
        self.assertEqual([p.name for p in work.iterdir() if p.name.endswith(".tmp")], [])

    def test_sites_and_visits(self):
        _, doc, prom = run("healthy")
        sites = doc["hosts"]["piabrota2"]["data"].get("domains", {}).get("list", [])
        for s in sites:
            self.assertIn(f'piabrota_site_up{{host="piabrota2",site="{s["name"]}"}} {int(s["up"])}', prom)
            if "views" in s:
                self.assertIn(f'piabrota_site_views_24h{{host="piabrota2",site="{s["name"]}"}} {s["views"]}', prom)

    def test_stale(self):
        _, doc, prom = run("stale")
        self.assertFalse(doc["hosts"]["piabrota"]["fresh"])
        self.assertEqual(doc["hosts"]["piabrota"]["age_s"], 120)
        self.assertIn('piabrota_host_fresh{host="piabrota"} 0', prom)
        self.assertIn('piabrota_sample_age_seconds{host="piabrota"} 120', prom)

    def test_missing(self):
        _, doc, prom = run("missing")
        self.assertEqual(sorted(doc["hosts"]), ["piabrota2"])
        self.assertIn("piabrota_hosts 1", prom)

    def test_hostile(self):
        _, doc, prom = run("hostile")
        self.assertEqual(sorted(doc["hosts"]), ["piabrota", "piabrota2"])
        self.check_format(prom)
        self.assertNotIn("Infinity", prom)
        self.assertNotIn("NaN", prom)

    def test_files_left_out(self):
        _, doc, prom = run(
            "missing",
            extra={
                "other.json": '{"host":"piabrota"}',
                "broken.json": "{",
                "Upper.json": '{"host":"Upper"}',
                "all.json": '{"host":"all"}',
                "big.json": '{"host":"big","x":"' + "a" * 70000 + '"}',
            },
        )
        self.assertEqual(sorted(doc["hosts"]), ["piabrota2"])
        self.check_format(prom)

    def test_empty_folder(self):
        work = Path(tempfile.mkdtemp())
        env = {**os.environ, "OUT_DIR": str(work)}
        subprocess.run(["sh", str(EXPORT)], env=env, check=True)
        self.assertEqual(json.loads((work / "all.json").read_text())["hosts"], {})
        self.assertIn("piabrota_hosts 0", (work / "metrics.prom").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=1)
