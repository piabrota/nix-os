#!/usr/bin/env python3
"""Dummy video pipeline: a smoke check of the render path (stages 5 to 7 of
docs/VIDEO-PIPELINE.md). It needs only ffmpeg and ffprobe. It tests nothing else.

  python3 video-lab/dummy/run.py      (just video-dummy)

VIDEO_LAB_OUT names the output folder (default video-lab/out/dummy). Prints `ARTIFACT OK: ...`
and writes report.json, or prints `ARTIFACT FAILED: ...` and exits 1.
"""

import json
import os
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path

SCENES = ["brief", "script", "voice", "visuals", "render"]
FREQS = [220, 262, 330, 392, 440]
COLOURS = [
    ("0x1d3557", "0xa8dadc"),
    ("0x6a040f", "0xf48c06"),
    ("0x1b4332", "0x95d5b2"),
    ("0x3c096c", "0xe0aaff"),
    ("0x03045e", "0x90e0ef"),
]
TIMES = []  # (seconds, peak KiB) of each ffmpeg run


def fail(msg):
    print(f"ARTIFACT FAILED: {msg}", file=sys.stderr)
    sys.exit(1)


def ff(*args):
    """ffmpeg at low priority, two threads; its time and the peak memory of the children so far."""
    start = time.monotonic()
    cmd = ["nice", "-n", "10", "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-threads", "2", *args]
    subprocess.run(cmd, check=True)
    TIMES.append((time.monotonic() - start, resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss))


def font():
    try:
        out = subprocess.run(["fc-list"], capture_output=True, text=True, check=False).stdout
    except OSError:
        return ""
    return next((line.split(":", 1)[0] for line in out.splitlines() if ".ttf" in line.lower()), "")


def stamp(ms):
    return f"00:00:{ms // 1000:02d},{ms % 1000:03d}"


def probe(file, *args):
    out = subprocess.run(
        ["ffprobe", "-v", "error", *args, "-of", "csv=p=0", str(file)], capture_output=True, text=True, check=False
    )
    return out.stdout.strip()


def main():
    out = Path(os.environ.get("VIDEO_LAB_OUT", "video-lab/out/dummy"))
    file, captions, tmp = out / "dummy.mp4", out / "captions.srt", out / "tmp"
    out.mkdir(parents=True, exist_ok=True)
    for f in (file, captions, out / "report.json"):
        f.unlink(missing_ok=True)
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir()

    ttf = font()
    if not ttf:
        print("No .ttf font found: the clips have no text.", file=sys.stderr)
    cues, start = [], 0
    for i, (name, (c0, c1), freq) in enumerate(zip(SCENES, COLOURS, FREQS), 1):
        text = f"Scene {i}: {name}"
        (tmp / f"text{i}.txt").write_text(text)
        vf = "null"
        if ttf:
            vf = (
                f"drawtext=fontfile={ttf}:textfile={tmp}/text{i}.txt:fontsize=64:fontcolor=white:borderw=3:"
                "bordercolor=black:x=(w-text_w)/2+120*sin(t):y=(h-text_h)/2+30*cos(t)"
            )
        # 1. Visuals: a moving gradient with a moving text.
        ff("-f", "lavfi", "-i", f"gradients=s=1280x720:r=25:d=6:c0={c0}:c1={c1}:speed=0.05",
           "-vf", f"{vf},format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", str(tmp / f"v{i}.mp4"))  # fmt: skip
        # 2. Voice: a tone. This stands in for the TTS stage (stage 3) of the spec.
        ff("-f", "lavfi", "-i", f"sine=f={freq}:r=44100:d=6", "-af", "afade=t=in:d=0.3,afade=t=out:st=5.7:d=0.3",
           "-ac", "2", str(tmp / f"a{i}.wav"))  # fmt: skip
        # 4. Captions: one cue for each scene. A scene starts every 5.5 s (6 s minus the 0.5 s fade).
        cues.append(f"{i}\n{stamp(start)} --> {stamp(start + 5000)}\n{text}\n")
        start += 5500
    captions.write_text("\n".join(cues) + "\n")

    # 3. Join: xfade for video, acrossfade for audio, then loudnorm.
    graph, prev, aprev = "", "[0:v]", "[5:a]"
    for n in range(1, 5):
        graph += f"{prev}[{n}:v]xfade=transition=fade:duration=0.5:offset={n * 5.5:.1f}[v{n}];"
        graph += f"{aprev}[{n + 5}:a]acrossfade=d=0.5[a{n}];"
        prev, aprev = f"[v{n}]", f"[a{n}]"
    graph += f"{aprev}loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000[aout]"
    inputs = [x for n in range(1, 6) for x in ("-i", str(tmp / f"v{n}.mp4"))]
    inputs += [x for n in range(1, 6) for x in ("-i", str(tmp / f"a{n}.wav"))]
    ff(*inputs, "-i", str(captions), "-filter_complex", graph, "-map", "[v4]", "-map", "[aout]", "-map", "10:0",
       "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p", "-r", "25",
       "-c:a", "aac", "-b:a", "128k", "-c:s", "mov_text", "-movflags", "+faststart", str(file))  # fmt: skip

    # 5. Report.
    if not file.is_file():
        fail("no output file")
    size = file.stat().st_size
    dur = float(probe(file, "-show_entries", "format=duration") or 0)
    streams = {k: len(probe(file, "-select_streams", k, "-show_entries", "stream=index").split()) for k in "vas"}
    vcodec = probe(file, "-select_streams", "v:0", "-show_entries", "stream=codec_name")
    acodec = probe(file, "-select_streams", "a:0", "-show_entries", "stream=codec_name")
    width, height = (
        int(x) for x in probe(file, "-select_streams", "v:0", "-show_entries", "stream=width,height").split(",")
    )
    wall = round(sum(t for t, _ in TIMES), 1)
    peak = max(m for _, m in TIMES) // 1024
    report = {
        "file": str(file), "bytes": size, "duration_s": round(dur, 1), "width": width, "height": height,
        "video_codec": vcodec, "audio_codec": acodec, "subtitle_tracks": streams["s"], "wall_s": wall, "peak_mib": peak,
    }  # fmt: skip
    (out / "report.json").write_text(json.dumps(report) + "\n")
    shutil.rmtree(tmp)

    # 6. Verdict.
    if size <= 102400:
        fail(f"file is {size} bytes, 100 KB or less")
    if streams["v"] != 1:
        fail(f"{streams['v']} video streams, expected 1")
    if streams["a"] != 1:
        fail(f"{streams['a']} audio streams, expected 1")
    if not 24 <= dur <= 32:
        fail(f"duration {dur:.1f} s, expected 24 to 32 s")
    print(
        f"ARTIFACT OK: {file} ({dur:.1f}s, {width}x{height}, {vcodec}+{acodec}, {size / 1048576:.1f} MiB, peak {peak} MiB)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
