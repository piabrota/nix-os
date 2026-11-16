package piabrota.pirsig

import BrainFixture.{figures, fullFigure, Leitura}

class VideosUnitTest extends munit.FunSuite:
  def tracks(s: String): CaptionTracks = CaptionTracks.parse(ujson.read(s))

  test("the choice of captions"):
    assertEquals(Videos.pickCaptions(tracks("""{"language": "pt-BR", "subtitles": {"en": [], "pt-BR": [], "live_chat": []},
      "automatic_captions": {"pt-orig": []}}""")), Some(Track("pt-BR", CaptionsKind.Manual)))
    assertEquals(Videos.pickCaptions(tracks("""{"language": "pt", "automatic_captions": {"en-orig": [], "pt-orig": []}}""")),
      Some(Track("pt-orig", CaptionsKind.Automatic)))
    assertEquals(Videos.pickCaptions(tracks("""{"language": "pt"}""")), None)

  test("the fallbacks of the captions"):
    assertEquals(Videos.pickCaptions(tracks("""{"language": "pt", "subtitles": {"en": []}}""")), Some(Track("en", CaptionsKind.Manual)))
    assertEquals(Videos.pickCaptions(tracks("""{"subtitles": {"en": [], "de": []}}""")), Some(Track("en", CaptionsKind.Manual)))
    assertEquals(Videos.pickCaptions(tracks("""{"language": "pt", "subtitles": {"live_chat": []},
      "automatic_captions": {"pt": []}}""")), None)
    assertEquals(Videos.pickCaptions(tracks("""{"automatic_captions": {"pt-orig": []}}""")), None)
    assertEquals(Videos.pickCaptions(tracks("""{"language": null, "subtitles": {"en": []}}""")), Some(Track("en", CaptionsKind.Manual)))

  test("the transcript in blocks of 30 s"):
    val events = ujson.read("""[{"tStartMs": 1000, "segs": [{"utf8": "olá"}]},
      {"tStartMs": 29000, "segs": [{"utf8": " mundo\n"}]},
      {"tStartMs": 31000, "segs": [{"utf8": "depois"}]}, {"tStartMs": 40000}]""").arr.toSeq
    assertEquals(Videos.transcript(Caption.parseAll(events)), "[00:00:00] olá mundo\n[00:00:30] depois\n")

  test("only https YouTube addresses"):
    for url <- List("https://youtu.be/abc", "https://www.YouTube.com/watch?v=x", "HTTPS://m.youtube.com/x",
        "https://user@youtube.com:443/watch") do
      assert(FetchInput.isYoutubeUrl(url), url)
    for url <- List("https://example.com/v", "http://youtube.com/watch?v=x", "https:youtube.com", "youtube.com/x",
        "https://youtube.com.evil.example/x") do
      assert(!FetchInput.isYoutubeUrl(url), url)

  test("times and slugs"):
    assertEquals(Videos.seconds("1:02:03"), 3723)
    assertEquals(Videos.seconds("45"), 45)
    assertEquals(intercept[BadData](Videos.seconds("1::2")).message, "invalid literal for int() with base 10: ''")
    assertEquals(Videos.clock(5025.9), "01:23:45")
    assertEquals(Videos.videoSlug("Uma Leitura: o começo, o meio"), "uma-leitura-o-comec-o")
    assertEquals(Videos.videoSlug("!!!"), "video")

  test("parse reports lines out of place"):
    val text = List("stray", "-> a: b", "### [k=x t=0:00-0:10] Early", "text of x", "-> y: because",
      "# Title", "## Part", "### Loose", "intro", "-> z: q").mkString("\n")
    val (doc, problems) = Videos.parse(text)
    assertEquals(problems, List(
      "link outside a note: -> a: b",
      "note before the first part: ### [k=x t=0:00-0:10] Early",
      "note without [k= t=]: ### Loose",
      "link outside a note: -> z: q"))
    assertEquals(doc, Doc("Title", List(
      Part("", notes = List(VideoNote("Early", "x", 0, 10, "text of x", List(Link("y", "because"))))),
      Part("Part", body = "intro"))))

  test("the reading time"):
    def doc(body: String, title: String = "") = Doc("", List(Part(title, body = body)))
    assertEquals(Videos.reading(doc("Uma frase. Outra frase.", title = "T")), Reading(5, 1.7, 0.0, 1))
    // 230 words are 0.97 min; a mean sentence over 20 words or over 25 % long words adds 15 %.
    assertEquals(Videos.reading(doc("palavra " * 230)), Reading(230, 230.0, 0.0, 2))
    val sentence = "extraordinario " * 5 + "palavra " * 4 + "fim. "
    assertEquals(Videos.reading(doc(sentence * 23)), Reading(230, 10.0, 0.5, 2))

class CheckDirTest extends munit.FunSuite:
  val f = FunFixture[BrainFixture](_ => BrainFixture(), f => os.remove.all(f.tmp))
  def problems(dir: os.Path): Seq[String] = Videos.checkDir(dir).json("problems").arr.toSeq.map(_.str)

  f.test("a good folder passes"): f =>
    val out = Videos.checkDir(f.folder(f.tmp / "2026-11-03-uma-leitura")).json
    assertEquals(out("problems"), ujson.Arr())
    assertEquals(out("covers").str, "00:02:00 of 00:02:00")
    assertEquals(out("notes").num, 2.0)
    assert(out("reading").str.startsWith("Leitura estimada: ~1 min ("), out)

  f.test("the problems"): f =>
    val bad = Leitura.replace("t=00:50-02:00", "t=01:10-01:30")
      .replace("O autor resume.", "O autor utiliza — vale ressaltar.").replace("-> fim: o fim", "-> nada: o fim")
    val found = problems(f.folder(f.tmp / "v", leitura = bad, figures = figures.tap(_("sobra") = ujson.Obj())))
    for expected <- List("gap 00:01:00-00:01:10", "stops at 00:01:30", "unknown link nada",
        "figure sobra is not in the text", "utilizar", "travessão", "enchimento") do
      assert(found.exists(_.contains(expected)), s"$expected: $found")

  f.test("the folder needs its files"): f =>
    val d = f.tmp / "empty"
    os.makeDir(d)
    assertEquals(Videos.checkDir(d).json, ujson.Obj("problems" -> ujson.Arr("no video.json", "no leitura.markdown", "no figuras.json")))

  f.test("notes and the figures file"): f =>
    val leitura = "# T\n## P\n### [k=a t=0:00-1:00] A\n-> a: \n### [k=a t=1:00-0:50] A again\n"
    val d = f.folder(f.tmp / "v", leitura = leitura)
    os.write.over(d / "figuras.json", "{not json")
    val found = problems(d)
    assertEquals(found.take(4), Seq("a: ends before it starts", "stops at 00:01:00 of 00:02:00",
      "repeated note keys", "a: link to a has no reason"))
    assert(found(4).startsWith("figuras.json is not JSON: "), found)
    assertEquals(found.size, 5)

  f.test("the figures"): f =>
    val leitura = Leitura.replace("![fig](mapa)", "![fig](mapa)\n\n![fig](semjson)\n\n![fig](Bad)\n\n![fig](ausente)")
    val d = f.folder(f.tmp / "v", leitura = leitura,
      figures = ujson.Obj("mapa" -> ujson.Obj("title" -> "x"), "semjson" -> fullFigure, "Bad" -> fullFigure))
    assertEquals(problems(d), Seq(
      "figure mapa: no alt", "figure mapa: no takeaway", "figure mapa: no read",
      "figure mapa: no missing", "figure mapa: no evidence",
      "figure semjson: no figuras/semjson.json (Archify's source)",
      "figure Bad: no figuras/Bad.json (Archify's source)",
      "figure ausente has no entry in figuras.json"))

  f.test("gramatico's mechanical rules, with Python's word boundaries"): f =>
    val body = "Ele utilizou. Reutilizar não conta. No âmbito de tudo. Realizar a tarefa. " +
      "O mesmo texto é bom. Ão mesmo texto é. Isto — aquilo."
    val leitura = Leitura.replace("O autor resume.", body)
    assertEquals(problems(f.folder(f.tmp / "v", leitura = leitura)), Seq(
      "travessão em prosa:  — ", "enchimento: No âmbito de", "`usar`, não `utilizar`: utilizou",
      "verbo pleno (PTW-4): Realizar a tarefa", "`o mesmo` como pronome (PTW-1): O mesmo"))

  extension (o: ujson.Obj) def tap(f: ujson.Obj => Unit): ujson.Obj = { f(o); o }

class VideosToolsTest extends munit.FunSuite:
  val name = "2026-11-03-uma-leitura"
  val info = ujson.Obj("id" -> "abc", "title" -> "Uma leitura", "upload_date" -> "20261103", "duration" -> 95,
    "webpage_url" -> "https://www.youtube.com/watch?v=abc", "channel" -> "Canal", "language" -> "pt")

  test("check over the server, and names that would leave the work folder"):
    val f = BrainFixture()
    f.folder(f.videoDir(name))
    val out = f.tool("pirsig_video_check", ujson.Obj("name" -> name))
    assertEquals(out.obj.keys.toList, List("passed", "notes", "figures", "covers", "reading", "minutes", "problems", "pending"))
    assertEquals(out("passed"), ujson.True)
    assertEquals(f.tool("pirsig_video_check", ujson.Obj("name" -> "../../etc")),
      ujson.Obj("error" -> "not a video folder name: '../../etc'"))
    assertEquals(f.tool("pirsig_video_check", ujson.Obj("name" -> "2026-11-03-nada")),
      ujson.Obj("passed" -> false, "problems" -> ujson.Arr("no video.json", "no leitura.markdown", "no figuras.json")))

  test("submit sends the reading but not the transcript"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    f.folder(f.videoDir(name))
    val out = f.tool("pirsig_video_submit", ujson.Obj("name" -> name, "request" -> "The owner asked to index a video."))
    assert(!out.obj.contains("error"), out)
    assertEquals(out("branch").str, "hermes/video-uma-leitura")
    val files = f.originFiles(out("branch").str)
    val base = s"brain/Videos/$name/"
    for file <- List("video.json", "leitura.markdown", "figuras.json", "figuras/mapa.json") do
      assert(files.contains(base + file), files)
    assert(!files.contains(base + "transcript.txt"))
    assertEquals(f.originShow(out("branch").str, base + "leitura.markdown"), Leitura)
    assert(os.read(f.ghLog).contains("--body-file"))

  test("submit refuses a folder that does not pass"):
    val f = BrainFixture()
    f.folder(f.videoDir(name), duration = 300)
    val out = f.tool("pirsig_video_submit", ujson.Obj("name" -> name, "request" -> "x"))
    assertEquals(out, ujson.Obj("error" -> "mcp__pirsig__pirsig_video_check does not pass; fix the folder first",
      "problems" -> ujson.Arr("stops at 00:02:00 of 00:05:00")))

  test("fetch refuses other hosts"):
    val f = BrainFixture()
    for url <- List("https://example.com/v", "http://youtube.com/watch?v=x") do
      assertEquals(f.tool("pirsig_video_fetch", ujson.Obj("url" -> url)), ujson.Obj("error" -> "give an https YouTube URL"))

  test("fetch writes the work folder"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    for (tracks, flag, kind, sub) <- List(
        ("automatic_captions" -> ujson.Obj("pt-orig" -> ujson.Arr()), "--write-auto-subs", "automatic", "pt-orig"),
        ("subtitles" -> ujson.Obj("pt" -> ujson.Arr()), "--write-subs", "manual", "pt")) do
      val f = BrainFixture()
      os.write(f.infoFile, ujson.write(ujson.Obj.from(info.value.toSeq :+ tracks)))
      val out = f.tool("pirsig_video_fetch", ujson.Obj("url" -> "https://youtu.be/abc"))
      assert(!out.obj.contains("error"), out)
      assertEquals((out("name").str, out("captions").str, out("captions_kind").str, out("duration").str),
        (name, sub, kind, "00:01:35"))
      assertEquals(out("transcript_words").num, 3.0) // the time stamp counts as a word
      assert(os.read(f.ytdlpLog).contains(s"$flag --sub-langs $sub --sub-format json3"), os.read(f.ytdlpLog))
      val d = f.videoDir(name)
      assertEquals(out("path").str, d.toString)
      assertEquals(os.read(d / "transcript.txt"), "[00:00:00] olá mundo\n")
      assert(os.isFile(d / "transcript.json3") && os.isDir(d / "figuras"))
      val video = os.read(d / "video.json")
      assert(video.startsWith("{\n  \"id\": \"abc\",\n  \"url\": "), video)
      assert(video.endsWith(s"\"captions_kind\": \"$kind\",\n  \"description\": null,\n  \"hub\": null,\n  \"resource\": null\n}\n"), video)

  test("fetch refuses without captions, on a bad answer, and for a known video"):
    assume(BrainFixture.gitThere, "git is not on the PATH")
    val f = BrainFixture()
    val url = ujson.Obj("url" -> "https://youtu.be/abc")
    os.write.over(f.infoFile, ujson.write(info))
    assert(f.tool("pirsig_video_fetch", url)("error").str.startsWith("no captions in the spoken language (pt)"))
    os.write.over(f.infoFile, ujson.write(ujson.Obj.from(info.value.toSeq.filter(_._1 != "upload_date") :+
      ("subtitles" -> ujson.Obj("pt" -> ujson.Arr())))))
    assertEquals(f.tool("pirsig_video_fetch", url), ujson.Obj("error" -> "yt-dlp gave an unexpected answer: 'upload_date'"))
    os.write.over(f.infoFile, ujson.write(ujson.Obj.from(info.value.toSeq :+ ("subtitles" -> ujson.Obj("pt" -> ujson.Arr())))))
    os.makeDir.all(f.home / "plugin-data" / "pirsig-videos" / "piabrota__pirsig" / "brain" / "Videos" / name)
    assert(f.tool("pirsig_video_fetch", url)("error").str.startsWith(s"$name is already in the brain"))
