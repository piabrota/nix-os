package piabrota.scripts

import piabrota.lib.TestKit

/** video-dummy with ffmpeg and ffprobe standing in: the captions, the report and the verdict. */
class VideoDummyTest extends munit.FunSuite:
  val ffmpeg = "#!/bin/sh\nfor a; do last=$a; done\nhead -c 200000 /dev/zero > \"$last\"\n"
  val ffprobe = """#!/bin/sh
                  |case "$*" in
                  |  *format=duration*) echo 27.5 ;;
                  |  *"-select_streams v -show_entries stream=index"*) echo 0 ;;
                  |  *"-select_streams a -show_entries stream=index"*) echo 1 ;;
                  |  *"-select_streams s -show_entries stream=index"*) echo 2 ;;
                  |  *"v:0 -show_entries stream=codec_name"*) echo h264 ;;
                  |  *"a:0 -show_entries stream=codec_name"*) echo aac ;;
                  |  *width,height*) echo 1280,720 ;;
                  |esac
                  |""".stripMargin

  test("stamp"):
    assertEquals(VideoDummy.stamp(27500), "00:00:27,500")

  test("a good artifact"):
    val cwd = os.temp.dir(prefix = "video")
    val r = TestKit.piabrota(Seq("video-dummy"), cwd = cwd,
      fakes = Some(TestKit.fakes("ffmpeg" -> ffmpeg, "ffprobe" -> ffprobe, "fc-list" -> "#!/bin/sh\nexit 1\n")))
    assertEquals(r.exitCode, 0, r.err.text())
    assert(r.out.text().matches(
      "ARTIFACT OK: video-lab/out/dummy/dummy.mp4 \\(27.5s, 1280x720, h264\\+aac, 0.2 MiB, peak \\d+ MiB\\)\n"), r.out.text())
    assert(r.err.text().contains("No .ttf font found: the clips have no text."), r.err.text())
    val out = cwd / "video-lab" / "out" / "dummy"
    assert(os.read(out / "report.json").matches(
      """\{"file": "video-lab/out/dummy/dummy.mp4", "bytes": 200000, "duration_s": 27.5, "width": 1280, """ +
        """"height": 720, "video_codec": "h264", "audio_codec": "aac", "subtitle_tracks": 1, "wall_s": \d+\.\d, "peak_mib": \d+\}\n"""),
      os.read(out / "report.json"))
    assert(os.read(out / "captions.srt").startsWith("1\n00:00:00,000 --> 00:00:05,000\nScene 1: brief\n\n2\n00:00:05,500"))
    assert(!os.exists(out / "tmp"))

  test("a short video fails"):
    val r = TestKit.piabrota(Seq("video-dummy"), cwd = os.temp.dir(), env = Map("VIDEO_LAB_OUT" -> "o"),
      fakes = Some(TestKit.fakes("ffmpeg" -> ffmpeg, "ffprobe" -> ffprobe.replace("echo 27.5", "echo 10"))))
    assertEquals(r.exitCode, 1)
    assert(r.err.text().contains("ARTIFACT FAILED: duration 10.0 s, expected 24 to 32 s"), r.err.text())
