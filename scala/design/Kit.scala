package piabrota.design

import piabrota.lib.die

/** The design kit of the piabrota sites (docs/DESIGN-KIT.md): functions that return HTML. Every
  * text argument is escaped. An argument that holds HTML says so: `body`, `head`, `icons`, `mark`
  * and the strings that `cardGrid` and `card` return. A link must be http(s), mailto or a relative
  * path.
  */
object Kit:
  private val fonts = """<link href="https://fonts.googleapis.com" rel="preconnect"><link crossorigin href="https://fonts.gstatic.com" rel="preconnect"><link href="https://fonts.googleapis.com/css2?family=Fjalla+One&amp;family=Inter:wght@400;600&amp;family=JetBrains+Mono&amp;display=swap" rel="stylesheet">"""

  /** Text as HTML. */
  def esc(text: String): String =
    val b = StringBuilder()
    text.foreach {
      case '&'  => b ++= "&amp;"
      case '<'  => b ++= "&lt;"
      case '>'  => b ++= "&gt;"
      case '"'  => b ++= "&quot;"
      case '\'' => b ++= "&#39;"
      case c    => b += c
    }
    b.result()

  private val scheme = "^[a-z][a-z0-9+.-]*:".r
  private val web = List("http:", "https:")
  private val mailto = "mailto:"

  /** A link target as an attribute value: http(s), mailto or a relative path. */
  def url(target: String): String =
    val s = Js.trim(target)
    val lower = Js.lowerAscii(s)
    val allowed = (mailto :: web).exists(lower.startsWith)
    if scheme.findPrefixOf(lower).isDefined && !allowed then
      die(s"design kit: link with a scheme that is not allowed: $s")
    esc(s)

  private def external(target: String): String =
    val lower = Js.lowerAscii(Js.trim(target))
    if web.exists(lower.startsWith) then """ rel="noopener"""" else ""

  /** The eye mark: the drawing of parts.eye (site/src/piabrota_site/parts.gleam), the only copy here. */
  def eye(size: Int = 28): String =
    s"""<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="pb-eye" height="$size" viewBox="0 0 100 100" width="$size"><rect fill="#BC2318" height="100" rx="22" width="100"></rect><path d="M12 50 Q50 18 88 50 Q50 82 12 50Z" fill="#F7F3EA"></path><circle cx="50" cy="50" fill="#2E9E4F" r="14"></circle><circle cx="50" cy="50" fill="#0B0D12" r="6"></circle></svg>"""

  /** The sites that a nav lists: the public ones. */
  def publicSites(sites: List[Site]): List[Site] = sites.filter(_.access == Access.Public)

  private def siteNav(sites: List[Site], current: String, cls: String): String =
    val links = publicSites(sites).map { s =>
      val here = if s.id == current then """ aria-current="page"""" else ""
      s"""<a href="${url(s.url)}"$here>${esc(s.label)}</a>"""
    }
    s"""<nav class="$cls" aria-label="piabrota sites">${links.mkString}</nav>"""

  private def known(sites: List[Site], current: String): Site =
    sites.find(_.id == current).getOrElse(die(s"""design kit: "$current" is not in design/sites.nix"""))

  /** The brand and the sites. `current` is the id of this site. As a `Header` it is the header of
    * a kit page (the brand, then the sites as one pill). As a `Bar` it is the 44 px strip that
    * design-inject puts into a foreign page: it carries the marker `data-pb-chrome`, and, when
    * `index` is the address of the site's index, a link back to it.
    */
  def chrome(current: String, sites: List[Site], form: Chrome = Chrome.Header): String =
    val site = known(sites, current)
    def brand(size: Int) = s"""<a class="pb-brand" href="https://www.piabrota.art/">${eye(size)}<span>piabrota</span></a>"""
    form match
      case Chrome.Header =>
        s"""<div class="pb-chrome pb-chrome--page"><div class="pb-wrap pb-chrome__in">${brand(30)}${siteNav(sites, current, "pb-nav")}</div></div>"""
      case Chrome.Bar(index) =>
        val back = index.filter(_.nonEmpty)
          .map(i => s"""<a class="pb-back" href="${url(i)}">← ${esc(site.label)} index</a>""")
          .getOrElse("")
        s"""<div class="pb-chrome pb-chrome--bar" $barMarker>${brand(22)}$back${siteNav(sites, current, "pb-nav")}</div>"""

  /** The attribute that marks the bar, so that a second design-inject leaves the page as it is. */
  val barMarker = "data-pb-chrome"

  /** The top band: the glow behind whatever it holds, usually a chrome and a hero. */
  def top(parts: String*): String = s"""<header class="pb-top">${parts.mkString}</header>"""

  /** The hero. `mark` is the HTML of a drawing (an inline SVG) that stands beside the text. An
    * empty text leaves its element out.
    */
  def hero(title: String, eyebrow: String = "", tail: String = "", lede: String = "",
      stats: Seq[Stat] = Nil, actions: Seq[Action] = Nil, mark: String = ""): String =
    val numbers =
      if stats.isEmpty then ""
      else s"""<dl class="pb-stats">${stats.map(s => s"<div><dt>${esc(s.label)}</dt><dd>${esc(s.value)}</dd></div>").mkString}</dl>"""
    val buttons =
      if actions.isEmpty then ""
      else
        val links = actions.map { a =>
          val variant = a.variant.css.fold("")(v => s" pb-btn--$v")
          s"""<a class="pb-btn$variant" href="${url(a.href)}"${external(a.href)}>${esc(a.label)}</a>"""
        }
        s"""<div class="pb-actions">${links.mkString}</div>"""
    val text =
      (if eyebrow.nonEmpty then s"""<p class="pb-eyebrow">${esc(eyebrow)}</p>""" else "") +
        s"""<h1 class="pb-title">${esc(title)}""" +
        (if tail.nonEmpty then s""" <span class="pb-tail">${esc(tail)}</span>""" else "") + "</h1>" +
        (if lede.nonEmpty then s"""<p class="pb-lede">${esc(lede)}</p>""" else "") + numbers + buttons
    val figure = if mark.nonEmpty then s"""<figure class="pb-hero__mark" aria-hidden="true">$mark</figure>""" else ""
    s"""<section class="pb-hero"><div class="pb-hero__text">$text</div>$figure</section>"""

  /** The sections of a page, in a main element: their `§` numbers count inside it. */
  def main(sections: String*): String = s"""<main class="pb-main" id="main">${sections.mkString}</main>"""

  /** A section with a numbered `§` heading. The number is counted by CSS, never typed. `note` is a
    * mono line on the right. `body` is HTML.
    */
  def section(id: String, title: String, body: String, count: Option[Int] = None, note: String = ""): String =
    val badge = count.map(n => s"""<span class="pb-count">$n</span>""").getOrElse("")
    val aside = if note.nonEmpty then s"""<span class="pb-note">${esc(note)}</span>""" else ""
    s"""<section class="pb-section" id="${esc(id)}"><div class="pb-section__head"><div class="pb-section__lead"><h2 class="pb-section__title">${esc(title)}</h2>$badge</div>$aside</div><div class="pb-section__body">$body</div></section>"""

  /** A small heading inside a section. */
  def sub(text: String): String = s"""<h3 class="pb-sub">${esc(text)}</h3>"""

  def pill(p: Pill): String =
    val tone = p.tone.css.fold("")(t => s" pb-pill--$t")
    s"""<span class="pb-pill$tone">${esc(p.text)}</span>"""

  /** One card. With `href` the title's link covers the card. */
  def card(title: String, line: String = "", foot: String = "", href: String = "", pills: Seq[Pill] = Nil): String =
    val tags = if pills.isEmpty then "" else s"""<div class="pb-card__pills">${pills.map(pill).mkString}</div>"""
    val name = if href.nonEmpty then s"""<a href="${url(href)}"${external(href)}>${esc(title)}</a>""" else esc(title)
    val lineHtml = if line.nonEmpty then s"""<p class="pb-card__line">${esc(line)}</p>""" else ""
    val footHtml = if foot.nonEmpty then s"""<p class="pb-card__foot">${esc(foot)}</p>""" else ""
    s"""<li class="pb-card">$tags<h3 class="pb-card__title">$name</h3>$lineHtml$footHtml</li>"""

  /** A grid of cards, from the strings that `card` returns. An empty list gives no grid. */
  def cardGrid(cards: Seq[String]): String =
    if cards.isEmpty then "" else s"""<ul class="pb-cards">${cards.mkString}</ul>"""

  /** The foot: one line of text and the public sites. */
  def footer(sites: List[Site], built: String, current: String): String =
    known(sites, current)
    s"""<footer class="pb-footer"><div class="pb-wrap pb-footer__in"><p>${esc(built)}</p>${siteNav(sites, current, "pb-footer__nav")}</div></footer>"""

  /** A whole page. `modules` names the CSS to inline after tokens and base, always in the order of
    * `Module.optional`. `icons` is the HTML of favicon/links.nix, `head` more HTML for the head,
    * `body` the HTML of the body. The page loads no script.
    */
  def page(css: Css, title: String, description: String, body: String, lang: String = Lang.default,
      modules: Seq[Module] = Nil, head: String = "", icons: String = ""): String =
    if title.isEmpty || description.isEmpty then die("design kit: a page needs a title and a description")
    val styles = (Module.always ++ Module.optional.filter(modules.contains)).map(css(_)).mkString
    s"""<!doctype html>\n<html lang="${esc(lang)}"><head><meta charset="utf-8"><meta content="width=device-width, initial-scale=1" name="viewport"><title>${esc(title)}</title><meta content="${esc(description)}" name="description"><meta content="#0B0D12" media="(prefers-color-scheme: dark)" name="theme-color"><meta content="#FFFFFF" media="(prefers-color-scheme: light)" name="theme-color">$icons$fonts<style>\n$styles</style>$head</head>\n<body>$body</body></html>\n"""
