package piabrota.pirsig

import piabrota.lib.{Sh, TestKit}

/** A bare `origin` with brain/Zettelkasten/10 ... .md on main, a stub gh, and `pirsig-mcp` run
  * over stdio against it: git reads https://github.com/piabrota/pirsig as the origin
  * (GIT_CONFIG_*), and HERMES_HOME is a temporary directory.
  */
final class BrainFixture:
  val tmp: os.Path = os.temp.dir(prefix = "pirsig")
  val origin: os.Path = tmp / "origin.git"
  val home: os.Path = tmp / "home"
  val ghLog: os.Path = tmp / "gh.log"
  val ytdlpLog: os.Path = tmp / "ytdlp.log"
  val infoFile: os.Path = tmp / "info.json"
  private val identity = Map("GIT_AUTHOR_NAME" -> "t", "GIT_AUTHOR_EMAIL" -> "t@t",
    "GIT_COMMITTER_NAME" -> "t", "GIT_COMMITTER_EMAIL" -> "t@t")

  val fakes: os.Path = TestKit.fakes(
    "gh" -> s"#!/bin/sh\nprintf '%s\\n' \"$$@\" >> $ghLog\necho https://github.com/piabrota/pirsig/pull/1\n",
    // yt-dlp: the info file is $infoFile; the captions are one event.
    "yt-dlp" -> s"""#!/bin/sh
      |echo "$$*" >> $ytdlpLog
      |out= sub= info=
      |while [ $$# -gt 0 ]; do
      |  case "$$1" in
      |    -o) out=$$2; shift ;;
      |    --sub-langs) sub=$$2; shift ;;
      |    --write-info-json) info=1 ;;
      |  esac
      |  shift
      |done
      |base=$${out%'%(ext)s'}
      |[ -n "$$info" ] && cp $infoFile "$${base}info.json"
      |[ -n "$$sub" ] && printf '%s' '{"events": [{"tStartMs": 1000, "segs": [{"utf8": "olá mundo"}]}]}' > "$$base$$sub.json3"
      |exit 0
      |""".stripMargin,
  )

  val env: Map[String, String] = identity ++ Map(
    "HERMES_HOME" -> home.toString,
    "GIT_CONFIG_COUNT" -> "1",
    "GIT_CONFIG_KEY_0" -> s"url.$origin.insteadOf",
    "GIT_CONFIG_VALUE_0" -> "https://github.com/piabrota/pirsig",
  )

  private def git(args: String*)(cwd: os.Path = tmp): Unit =
    os.proc("git" +: args).call(cwd = cwd, env = identity, stdout = os.Pipe, stderr = os.Pipe)

  // Without git (the Nix build's sandbox) only the tools that need no checkout can run.
  if BrainFixture.gitThere then
    val seed = tmp / "seed"
    git("init", "--quiet", "--bare", "-b", "main", origin.toString)()
    os.write(seed / "brain" / "Zettelkasten" / "10 Repo awesome-ocean-science.md", BrainFixture.Note10, createFolders = true)
    os.write(seed / ".claude" / "agents" / "video-indexer.md", "policy\n", createFolders = true)
    os.write(seed / "src" / "main.rs", "fn main() {}\n", createFolders = true)
    git("init", "--quiet", "-b", "main")(seed)
    git("add", ".")(seed)
    git("commit", "--quiet", "-m", "seed")(seed)
    git("push", "--quiet", origin.toString, "main")(seed)

  /** The answers of `piabrota pirsig-mcp` to these requests, one per line. */
  def session(requests: ujson.Value*)(extraEnv: Map[String, String] = Map.empty): List[ujson.Value] =
    val r = TestKit.piabrota(Seq("pirsig-mcp"), env = env ++ extraEnv, stdin = requests.map(ujson.write(_)).mkString("", "\n", "\n"),
      fakes = Some(fakes))
    assert(r.exitCode == 0, r.err.text())
    r.out.lines().toList.map(ujson.read(_))

  /** One tools/call; its text is the plugin's JSON answer. */
  def tool(name: String, args: ujson.Obj, extraEnv: Map[String, String] = Map.empty): ujson.Value =
    val answers = session(BrainFixture.call(name, args))(extraEnv)
    ujson.read(answers.head("result")("content")(0)("text").str)

  def originFiles(branch: String): List[String] =
    os.proc("git", "--git-dir", origin, "ls-tree", "-r", "--name-only", branch).call().out.lines().toList

  def originShow(branch: String, path: String): String =
    os.proc("git", "--git-dir", origin, "show", s"$branch:$path").call().out.text()

  /** A video's work folder as pirsig_video_fetch leaves it, with a reading. */
  def folder(dir: os.Path, leitura: String = BrainFixture.Leitura, figures: ujson.Value = BrainFixture.figures,
      duration: Int = 120): os.Path =
    os.makeDir.all(dir / "figuras")
    os.write.over(dir / "video.json", ujson.write(ujson.Obj("id" -> "abc", "url" -> "https://www.youtube.com/watch?v=abc",
      "title" -> "Uma leitura", "duration" -> duration, "captions" -> "pt-orig", "captions_kind" -> "automatic")))
    os.write.over(dir / "leitura.markdown", leitura)
    os.write.over(dir / "figuras.json", ujson.write(figures))
    os.write.over(dir / "figuras" / "mapa.json", "{}")
    os.write.over(dir / "transcript.txt", "[00:00:00] olá\n")
    dir

  def videoDir(name: String): os.Path = home / "plugin-data" / "pirsig-videos" / "videos" / name

object BrainFixture:
  def gitThere: Boolean = Sh.which("git").isDefined

  val Note10: String = """---
    |pirsig: note
    |zid: "10"
    |title: "Repo: awesome-ocean-science"
    |kind: literature
    |---
    |
    |# Repo: awesome-ocean-science
    |
    |An index of ocean data.
    |""".stripMargin

  val Leitura: String = """# Uma leitura
    |
    |## Como ler este texto
    |O texto relata o que o autor diz.
    |
    |## Parte 1: Começo
    |### [k=abertura t=00:00-01:00] O autor abre o vídeo
    |-> fim: o fim responde à abertura
    |
    |O autor apresenta o tema.
    |
    |![fig](mapa)
    |
    |### [k=fim t=00:50-02:00] O autor fecha o vídeo
    |-> #10: o índice de dados do oceano
    |
    |O autor resume.
    |
    |## O que não foi checado
    |Nada.
    |""".stripMargin

  def fullFigure: ujson.Obj = ujson.Obj.from(FigureField.values.toList.map(_.key -> ujson.Str("x")))
  def figures: ujson.Obj = ujson.Obj("mapa" -> fullFigure)

  def call(name: String, args: ujson.Obj): ujson.Obj =
    ujson.Obj("jsonrpc" -> "2.0", "id" -> 1, "method" -> "tools/call",
      "params" -> ujson.Obj("name" -> name, "arguments" -> args))

  /** A note as the model sends it, with `over` replacing fields. */
  def note(over: (String, ujson.Value)*): ujson.Obj =
    val n = ujson.Obj(
      "title" -> "Links beat folders", "type" -> "fleeting", "status" -> "unverified",
      "body" -> "Uma nota ligada volta a aparecer quando outra ideia chama por ela.",
      "links" -> ujson.Arr(ujson.Obj("target" -> "10 Repo awesome-ocean-science", "why" -> "an example of an index")),
    )
    over.foreach((k, v) => n(k) = v)
    n
