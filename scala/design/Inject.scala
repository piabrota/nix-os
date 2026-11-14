package piabrota.design

import piabrota.lib.{die, env, warn}

/** `design-inject`, a build step of proof-site/common.nix: puts the brand bar (`Kit.chrome` with
  * `bar`) into every .html file of a folder that came from another repository. It adds one element
  * and one `<style>` right after the opening `<body>` tag, and touches nothing else: not the page's
  * CSS, not its scripts, not its text. Every selector of the bar's CSS holds the class .pb-chrome,
  * so no rule of the page reaches the bar and none of the bar's reaches the page. The marker
  * `data-pb-chrome` makes a second run a no-op.
  *
  *   design-inject inject <dir> --current <id> --sites <sites.json> [--index <href>]
  *   design-inject check <dir> [--except <relative path>]...
  */
object Inject:
  val marker: String = Kit.barMarker

  // An archify page puts its toolbar at the top with `position: absolute` above 720 px, so the bar
  // would sit under it. This rule moves the toolbar down by the bar's height (44 px and its two
  // margins) on a page that has the bar, and not in presentation or embed mode, where the bar is
  // hidden. It holds the bar's class in its selector and sets the toolbar's margin only.
  private val archifyToolbar = """@media (min-width: 721px) { html:not([data-embed="true"]):not([data-present="true"]) .pb-chrome--bar ~ .toolbar { margin-top: 68px; } }"""

  private val rootBlock = s":root${Js.space}*\\{([^}]*)\\}".r
  private val comment = """/\*[\s\S]*?\*/""".r
  private val lineBreak = s"\n${Js.space}*".r
  // Both match on `Js.lowerAscii` of the page. The <body> that follows </head>, else the first one:
  // a script string cannot fool the first form.
  private val bodyAfterHead = s"</head>(?:${Js.space}|<!--[\\s\\S]*?-->)*<body\\b[^>]*>".r
  private val anyBody = """<body\b[^>]*>""".r

  /** The bar's CSS: the dark tokens declared on the bar itself (so it is dark in any theme), then
    * chrome.css.
    */
  def barStyle(css: Css, html: String = ""): String =
    val tokens = rootBlock.findFirstMatchIn(css(Module.Tokens)).getOrElse(die("design kit: tokens.css has no :root block"))
    val dark = tokens.group(1).split(';').map(Js.trim).filter(_.startsWith("--")).mkString(";")
    val chrome = Js.trim(lineBreak.replaceAllIn(comment.replaceAllIn(css(Module.Chrome), ""), " "))
    val rules = s".pb-chrome--bar{$dark}\n$chrome"
    if Archify.drew(html) then s"$rules\n$archifyToolbar" else rules

  /** The page with the bar after its <body> tag. Dies when it has no <body>. */
  def injectHtml(css: Css, html: String, current: String, sites: List[Site], index: Option[String],
      name: String = "page"): String =
    if html.contains(marker) then html
    else
      val lower = Js.lowerAscii(html)
      val tag = bodyAfterHead.findFirstMatchIn(lower).orElse(anyBody.findFirstMatchIn(lower))
        .getOrElse(die(s"$name: no <body> tag, so the brand bar has no place to go"))
      val at = tag.end
      html.substring(0, at) + s"<style>${barStyle(css, html)}</style>" +
        Kit.chrome(current, sites, Chrome.Bar(index)) + html.substring(at)

  /** Every .html file under a folder, sorted. Links are not followed. */
  def htmlFiles(dir: os.Path): Seq[os.Path] =
    os.walk(dir).filter(p => p.last.endsWith(Layout.html) && os.isFile(p, followLinks = false)).sortBy(_.toString)

  /** Puts the bar into every .html file of a folder. Returns how many files it changed. */
  def injectDir(css: Css, dir: os.Path, current: String, sites: List[Site], index: Option[String]): Int =
    htmlFiles(dir).count { file =>
      val before = os.read(file)
      val after = injectHtml(css, before, current, sites, index, file.relativeTo(dir).toString)
      if after != before then os.write.over(file, after)
      after != before
    }

  /** The .html files of a folder with no bar, except the paths (relative to the folder) in `except`. */
  def withoutBar(dir: os.Path, except: Seq[String]): Seq[String] =
    htmlFiles(dir).map(_.relativeTo(dir).toString)
      .filterNot(except.contains)
      .filterNot(f => os.read(dir / os.RelPath(f)).contains(marker))

  private val usage = "usage: design-inject inject|check <dir> ..."

  def run(args: List[String]): Int = args match
    case "inject" :: dir :: rest =>
      val f = Flags.parse(rest)
      val (current, sitesFile) = (f.first("current"), f.first("sites")) match
        case (Some(c), Some(s)) => (c, s)
        case _ => die(s"$usage\n  design-inject inject <dir> --current <id> --sites <sites.json> [--index <href>]")
      val root = os.Path(dir, os.pwd)
      val sites = Site.parseAll(ujson.read(os.read(os.Path(sitesFile, os.pwd)))).fold(e => die(s"$sitesFile: $e"), identity)
      val css = Css.locate(env(Css.envVar), os.pwd).fold(die(_), identity)
      val n = injectDir(css, root, current, sites, f.first("index"))
      warn(s"brand bar: $n of ${htmlFiles(root).size} pages changed in $dir")
      0
    case "check" :: dir :: rest =>
      val except = Flags.parse(rest).all("except")
      val bad = withoutBar(os.Path(dir, os.pwd), except)
      if bad.nonEmpty then die(s"no brand bar in: ${bad.mkString(", ")}")
      warn(s"brand bar: every page of $dir has it, except ${if except.isEmpty then "none" else except.mkString(", ")}")
      0
    case _ => die(usage)
