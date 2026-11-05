//// Writes a plain HTML view of the skills: one index page, one page for each
//// skill and one page for `docs/awesome-skills.md`. The index also lists the
//// skills of other authors from `docs/common-skills.md`. The agents have
//// their own index: `agents.html` from `agents/README.md`, and one page for each
//// agent file in `agents/`. Run it from `www/` with `gleam run` (or `just site`).

import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string

const skills_dir = "../skills"

const out_dir = "../docs/site"

const awesome_md = "../docs/awesome-skills.md"

const common_md = "../docs/common-skills.md"

const agents_dir = "../agents"

const tags_txt = "tags.txt"

const logo_svg = "../docs/drawings/waza.svg"

@external(erlang, "www_ffi", "read")
fn read(path: String) -> Result(String, Nil)

@external(erlang, "www_ffi", "write")
fn write(path: String, text: String) -> Nil

@external(erlang, "www_ffi", "list_dir")
fn list_dir(path: String) -> List(String)

@external(erlang, "www_ffi", "is_dir")
fn is_dir(path: String) -> Bool

@external(erlang, "www_ffi", "make_dir")
fn make_dir(path: String) -> Nil

pub type Skill {
  Skill(
    category: String,
    name: String,
    description: String,
    manual: Bool,
    tags: List(String),
    body: String,
    url: String,
  )
}

pub fn main() -> Nil {
  let tags = read_tags()
  let skills = add_tags(load_skills(), tags)
  let common = add_tags(load_common(), tags)
  make_dir(out_dir)
  let assert Ok(logo) = read(logo_svg)
  write(out_dir <> "/waza.svg", logo)
  write(out_dir <> "/index.html", index_page(skills, common, logo))
  write(out_dir <> "/awesome-skills.html", awesome_page())
  let agents = load_agents()
  write(out_dir <> "/agents.html", agents_page())
  list.each(agents, fn(a) {
    write(out_dir <> "/agent-" <> a.name <> ".html", agent_page(a))
  })
  let prevs = [Error(Nil), ..list.map(skills, Ok)]
  let nexts = list.append(list.drop(list.map(skills, Ok), 1), [Error(Nil)])
  list.zip(skills, list.zip(prevs, nexts))
  |> list.each(fn(item) {
    let #(s, #(prev, next)) = item
    write(out_dir <> "/" <> s.name <> ".html", skill_page(s, prev, next))
  })
  io.println(
    "Wrote "
    <> string.inspect(list.length(skills) + list.length(agents) + 3)
    <> " pages to docs/site/",
  )
}

fn load_skills() -> List(Skill) {
  sorted_dirs(skills_dir)
  |> list.flat_map(fn(category) {
    sorted_dirs(skills_dir <> "/" <> category)
    |> list.filter_map(fn(name) {
      let path = skills_dir <> "/" <> category <> "/" <> name <> "/SKILL.md"
      case read(path) {
        Ok(text) -> Ok(parse(category, name, text))
        Error(_) -> Error(Nil)
      }
    })
  })
}

/// Reads the table of `docs/common-skills.md`. A row is
/// `| `name` | [owner/repo](url) | licence | text | install |`. The category of
/// each one is `elsewhere`, and its link goes to its repository.
fn load_common() -> List(Skill) {
  let assert Ok(text) = read(common_md)
  text
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.split(line, " | ") {
      ["| `" <> name, repo, _licence, what, _install] -> {
        use #(_, url) <- result.try(string.split_once(repo, "]("))
        Ok(Skill(
          category: "elsewhere",
          name: string.replace(name, "`", ""),
          description: what,
          manual: False,
          tags: [],
          body: "",
          url: string.drop_end(url, 1),
        ))
      }
      _ -> Error(Nil)
    }
  })
}

/// Reads `tags.txt`: one line `name: tag tag` for each skill.
fn read_tags() -> List(#(String, List(String))) {
  let assert Ok(text) = read(tags_txt)
  text
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.starts_with(line, "#") {
      True -> Error(Nil)
      False -> {
        use #(name, tags) <- result.try(string.split_once(line, ":"))
        Ok(#(string.trim(name), string.split(string.trim(tags), " ")))
      }
    }
  })
}

/// Gives each skill its category, its tags from `tags.txt` and `manual` for a
/// ⏸ skill. A skill with no line in `tags.txt` stops the build.
fn add_tags(
  skills: List(Skill),
  tags: List(#(String, List(String))),
) -> List(Skill) {
  list.map(skills, fn(s) {
    let listed = case list.key_find(tags, s.name) {
      Ok(t) -> t
      Error(_) -> panic as { "www/tags.txt has no line for " <> s.name }
    }
    let manual = case s.manual {
      True -> ["manual"]
      False -> []
    }
    Skill(..s, tags: list.unique(list.flatten([[s.category], listed, manual])))
  })
}

fn sorted_dirs(path: String) -> List(String) {
  list_dir(path)
  |> list.filter(fn(e) { is_dir(path <> "/" <> e) })
  |> list.sort(string.compare)
}

/// Splits the front matter from the body. A field can continue on an
/// indented line, as `scripts/check.py` reads it.
pub fn parse(category: String, name: String, text: String) -> Skill {
  let #(front, body) = case string.split_once(text, "---\n") {
    Ok(#("", rest)) ->
      case string.split_once(rest, "\n---\n") {
        Ok(parts) -> parts
        Error(_) -> #("", text)
      }
    _ -> #("", text)
  }
  let fields = fields(string.split(front, "\n"), [])
  Skill(
    category: category,
    name: name,
    description: field(fields, "description"),
    manual: field(fields, "disable-model-invocation") == "true",
    tags: [],
    body: string.trim(body),
    url: "",
  )
}

fn fields(
  lines: List(String),
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  case lines, acc {
    [], _ -> acc
    [line, ..rest], [#(key, value), ..done] ->
      case string.starts_with(line, " ") {
        True ->
          fields(rest, [#(key, value <> " " <> string.trim(line)), ..done])
        False -> fields(rest, new_field(line, acc))
      }
    [line, ..rest], [] -> fields(rest, new_field(line, acc))
  }
}

fn new_field(
  line: String,
  acc: List(#(String, String)),
) -> List(#(String, String)) {
  case string.split_once(line, ":") {
    Ok(#(key, value)) -> [#(key, string.trim(value)), ..acc]
    Error(_) -> acc
  }
}

fn field(fields: List(#(String, String)), key: String) -> String {
  case list.key_find(fields, key) {
    Ok(value) -> unquote(value)
    Error(_) -> ""
  }
}

fn unquote(value: String) -> String {
  case string.starts_with(value, "\"") && string.ends_with(value, "\"") {
    True ->
      value
      |> string.drop_start(1)
      |> string.drop_end(1)
      |> string.replace("\\\"", "\"")
    False -> value
  }
}

pub fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}

const repo_url = "https://github.com/piabrota/skills"

const home_url = "https://www.piabrota.art/"

/// The look of www.piabrota.art (site/DESIGN.md in piabrota/nix-os): its tokens, its type and its
/// shapes. Change them there first. Quotes in the CSS are single, so that the string needs no escape.
const style =
  "
:root {
  --bg: #0B0D12; --surface: #14171F; --raised: #1A1E28; --border: #2A303C;
  --text: #EDEFF3; --muted: #9AA3B2;
  --accent: #BC2318; --accent-text: #FF6B5E; --on-accent: #FFFFFF;
  --radius: 12px;
  --display: 'Fjalla One', 'Arial Narrow', sans-serif;
  --mono: 'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;
  color-scheme: dark;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #FFFFFF; --surface: #F4F5F7; --raised: #FFFFFF; --border: #D8DCE3;
    --text: #0B0D12; --muted: #4F5868; --accent-text: #A51D14;
    color-scheme: light;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; scroll-padding-top: 64px; }
body { margin: 0; background: var(--bg); color: var(--text); font: 400 15px/1.55 Inter, system-ui, -apple-system, 'Segoe UI', sans-serif; }
[hidden] { display: none !important; }
a { color: var(--accent-text); text-decoration: none; }
a:hover { text-decoration: underline; text-underline-offset: 3px; }
:focus-visible { outline: 2px solid var(--accent-text); outline-offset: 3px; }
h1, h2, h3, h4 { font-family: var(--display); font-weight: 400; margin: 0; text-wrap: balance; }
.btn, .tag, .sections a, .search { touch-action: manipulation; }
code { font: 400 .9em var(--mono); padding: 1px 6px; background: var(--raised); border: 1px solid var(--border); border-radius: 6px; overflow-wrap: anywhere; }
.skip { position: absolute; left: 12px; top: -64px; z-index: 10; padding: 12px 18px; border-radius: 999px; background: var(--accent); color: var(--on-accent); font-weight: 600; }
.skip:focus { top: 12px; }
.wrap { max-width: 1040px; margin: 0 auto; padding: 0 20px; }

/* The top band: the glow, the bar, the hero. */
.top { border-bottom: 1px solid var(--border); background: radial-gradient(60rem 22rem at 8% -30%, color-mix(in srgb, var(--accent) 26%, transparent), transparent 70%), var(--bg); padding-bottom: 48px; }
.bar { display: flex; align-items: center; justify-content: space-between; gap: 12px 16px; flex-wrap: wrap; padding-top: 20px; padding-bottom: 20px; }
.brand { display: inline-flex; align-items: center; gap: 10px; color: var(--text); font: 400 1.35rem/1 var(--display); letter-spacing: .01em; }
.brand:hover { text-decoration: none; }
.eye { display: block; flex: none; }
.sections { display: inline-flex; flex-wrap: wrap; gap: 2px; padding: 3px; border: 1px solid var(--border); border-radius: 999px; background: var(--surface); }
.sections a { padding: 9px 14px; border-radius: 999px; font: 400 12px/1 var(--mono); color: var(--muted); }
.sections a:hover { text-decoration: none; color: var(--text); background: var(--raised); }
.sections a[aria-current='page'] { background: var(--accent); color: var(--on-accent); }
.hero { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 24px 48px; align-items: center; padding-top: 32px; }
.eyebrow { margin: 0 0 12px; font: 600 12px/1.4 Inter, sans-serif; letter-spacing: .18em; text-transform: uppercase; color: var(--accent-text); }
.eyebrow a { color: inherit; }
h1 { font-size: clamp(2.4rem, 6.5vw, 4rem); line-height: 1.04; letter-spacing: .005em; overflow-wrap: anywhere; }
h1 span { color: var(--muted); }
.lede { max-width: 60ch; color: var(--muted); font-size: 1.05rem; margin: 16px 0 0; }
.lede a, .sub a, .prose a, .foot p a { text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 3px; }
.drawing { margin: 0; text-align: center; }
.drawing svg { display: block; margin: 0 auto; width: 200px; height: auto; filter: drop-shadow(0 18px 40px color-mix(in srgb, var(--accent) 35%, transparent)); }
.drawing .l { fill: none; stroke: var(--accent-text); stroke-linecap: round; stroke-linejoin: round; }
.drawing .d { fill: var(--accent-text); stroke: none; }
.drawing figcaption { margin-top: 10px; font: 400 12px/1 var(--mono); color: var(--muted); }
.metrics { display: flex; flex-wrap: wrap; gap: 12px 36px; margin: 24px 0 0; }
.metrics div { display: flex; flex-direction: column-reverse; }
.metrics dd { margin: 0; font: 400 2rem/1.1 var(--display); }
.metrics dt { font-size: 13px; color: var(--muted); }
.chips { display: flex; flex-wrap: wrap; gap: 8px; }
.hero .chips { margin-top: 20px; }

/* Buttons: one filled pill a row, the rest outlined. */
.actions { display: flex; flex-wrap: wrap; gap: 10px; margin-top: 26px; }
.btn { display: inline-flex; align-items: center; gap: 8px; min-height: 44px; padding: 0 20px; font: 600 14px/1 Inter, sans-serif; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: 999px; cursor: pointer; list-style: none; transition: border-color .15s ease, background-color .15s ease, transform .15s ease; }
.btn::-webkit-details-marker { display: none; }
.btn svg { fill: currentColor; flex: none; }
.btn:hover { text-decoration: none; border-color: var(--accent-text); transform: translateY(-1px); }
.btn:active { transform: none; background: var(--raised); }
.btn.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.btn.primary:hover { background: color-mix(in srgb, var(--accent) 86%, white); border-color: color-mix(in srgb, var(--accent) 86%, white); }
.btn.copy { min-height: 36px; padding: 0 14px; font-size: 13px; margin-left: auto; }
.actions.small { margin: 0; gap: 8px; }
.stars:not(:empty) { padding-left: 8px; border-left: 1px solid var(--border); font-family: var(--mono); font-weight: 400; }

/* Sections: a numbered head (§ 01, § 02, counted here, never typed). */
main { counter-reset: sec; }
main > section.wrap { padding-top: 56px; padding-bottom: 8px; }
.section-head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.section-head h2, .prose h2 { font-size: 2rem; counter-increment: sec; overflow-wrap: anywhere; }
.section-head h2::before, .prose h2::before { content: '§ ' counter(sec, decimal-leading-zero) '  '; font: 400 .8rem/1 var(--mono); color: var(--accent-text); vertical-align: .55em; white-space: pre; }
.source { font: 400 12px/1 var(--mono); color: var(--muted); }
.sub { color: var(--muted); margin: 6px 0 8px; max-width: 70ch; }

/* The commands: a terminal on the surface, as /hermes shows its YAML. */
.installs { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 420px), 1fr)); gap: 14px; margin-top: 18px; }
.terminal { border: 1px solid var(--border); border-radius: var(--radius); background: var(--surface); overflow: hidden; font: 400 13px/1.6 var(--mono); min-width: 0; }
.term-bar { display: flex; align-items: center; gap: 14px; padding: 8px 12px 8px 16px; border-bottom: 1px solid var(--border); color: var(--muted); font-size: 12px; background: var(--raised); }
.term-title { min-width: 0; overflow-wrap: anywhere; }
.dots { display: inline-flex; gap: 7px; }
.dots i { width: 11px; height: 11px; border-radius: 50%; background: var(--accent); }
.dots i:nth-child(2) { background: var(--muted); }
.dots i:nth-child(3) { background: var(--border); }
.terminal pre { margin: 0; padding: 16px 20px; color: var(--text); font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 2; }
.terminal pre.sh::before { content: '$ '; color: var(--accent-text); }
.cite { margin: 0; }
.cite[open] { flex-basis: 100%; }
.cite-box { display: grid; gap: 12px; margin-top: 12px; max-width: 720px; }
.cite-box p { margin: 0; }

/* The search and the tags. */
.finder { display: grid; gap: 14px; margin-top: 18px; padding: 18px 20px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); }
.search { width: 100%; min-height: 44px; padding: 0 20px; font: 400 15px/1.5 Inter, system-ui, sans-serif; color: var(--text); background: var(--bg); border: 1px solid var(--border); border-radius: 999px; transition: border-color .15s ease; }
.search::placeholder { color: var(--muted); opacity: 1; }
.search:hover { border-color: var(--muted); }
.search:focus-visible { border-color: transparent; outline-offset: 2px; }
.tag { display: inline-flex; align-items: center; gap: 6px; padding: 5px 11px; font: 400 12px/1.3 var(--mono); color: var(--text); background: var(--bg); border: 1px solid var(--border); border-radius: 999px; transition: border-color .15s ease, background-color .15s ease; }
.tag .n { color: var(--muted); }
.tag:hover { text-decoration: none; border-color: var(--accent-text); }
.tag.on { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.tag.on .n { color: var(--on-accent); }
.found { margin: 0; font: 400 12px/1.4 var(--mono); color: var(--muted); }
.found:empty { display: none; }
.empty { display: flex; align-items: center; justify-content: space-between; gap: 12px 20px; flex-wrap: wrap; margin-top: 18px; padding: 18px 20px; color: var(--muted); border: 1px dashed var(--border); border-radius: var(--radius); }
.empty p { margin: 0; }

/* The anchors stay at the top while the page scrolls. */
.anchors { position: sticky; top: 0; z-index: 2; background: color-mix(in srgb, var(--bg) 92%, transparent); border-bottom: 1px solid var(--border); backdrop-filter: blur(8px); }
.anchors .wrap { display: flex; gap: 4px 20px; overflow-x: auto; padding-top: 8px; padding-bottom: 8px; white-space: nowrap; scrollbar-width: none; }
.anchors a { padding: 6px 0; font-size: 13px; color: var(--muted); }
.anchors a:hover { color: var(--text); }
.anchors span { margin-left: 4px; font: 400 11px var(--mono); }

/* The skills: a lane for each category, a card for each skill. */
.lane { margin-top: 34px; }
.lane h3 { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; font: 600 12px/1 Inter, sans-serif; letter-spacing: .16em; text-transform: uppercase; color: var(--muted); }
.count { font: 400 11px/1 var(--mono); letter-spacing: 0; color: var(--text); border: 1px solid var(--border); border-radius: 999px; padding: 3px 7px; }
.cards { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr)); gap: 14px; }
.card { position: relative; display: flex; flex-direction: column; gap: 10px; min-width: 0; padding: 18px 20px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); transition: border-color .15s ease, transform .15s ease; }
.card:hover, .card:focus-within { border-color: var(--accent-text); }
.card:hover { transform: translateY(-2px); }
.card-name { font-size: 1.45rem; line-height: 1.1; overflow-wrap: anywhere; }
.card-name a { color: var(--text); }
.card-name a:hover { text-decoration: none; }
.card-name a::after { content: ''; position: absolute; inset: 0; border-radius: inherit; }
.desc { margin: 0 0 auto; color: var(--muted); font-size: 14px; overflow-wrap: anywhere; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 5; line-clamp: 5; overflow: hidden; }
.card-tags { position: relative; z-index: 1; display: flex; flex-wrap: wrap; gap: 6px; margin: 0; padding-top: 10px; border-top: 1px solid var(--border); }
.card .tag { padding: 3px 9px; font-size: 11px; background: var(--raised); }
.card .tag:hover { background: var(--bg); }

/* A skill, an agent: its file in the terminal; the other pages. */
.terminal pre.doc { padding: 18px 20px; }
.pager { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap; margin-top: 28px; }
.pager .btn { height: auto; padding-top: 12px; padding-bottom: 12px; line-height: 1.2; overflow-wrap: anywhere; }
.prose { padding-bottom: 8px; }
.prose > p, .prose > ul { max-width: 72ch; color: var(--muted); }
.prose ul { padding-left: 1.3em; }
.prose h2 { margin-top: 48px; margin-bottom: 14px; }
.scroll { margin: 18px 0; overflow-x: auto; border: 1px solid var(--border); border-radius: var(--radius); background: var(--surface); }
table { border-collapse: collapse; width: 100%; min-width: 36rem; font-size: 14px; }
th, td { text-align: left; vertical-align: top; padding: 12px 16px; border-bottom: 1px solid var(--border); overflow-wrap: break-word; }
tr:last-child td { border-bottom: 0; }
th { font: 600 11px/1.4 Inter, sans-serif; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); background: var(--raised); }
td { color: var(--muted); }
td:first-child, td:nth-child(2) { color: var(--text); }

/* The foot. */
.foot { margin-top: 64px; border-top: 1px solid var(--border); padding: 28px 0 48px; font-size: 13px; color: var(--muted); }
.foot-in { display: flex; flex-direction: column; align-items: flex-start; gap: 14px; }
.foot p { margin: 0; max-width: 70ch; }
.foot a { white-space: nowrap; }
.orgs a { color: var(--muted); text-decoration: underline; text-decoration-color: var(--border); text-underline-offset: 4px; }
.orgs a:hover { text-decoration-color: var(--accent-text); }

@media (max-width: 760px) {
  .hero { grid-template-columns: minmax(0, 1fr); }
  .drawing { order: -1; justify-self: start; }
  .drawing svg { width: 96px; }
  .drawing figcaption { display: none; }
  .section-head h2, .prose h2 { font-size: 1.7rem; }
}
@media (max-width: 560px) {
  .scroll { overflow: visible; margin: 18px 0; border: 0; background: none; }
  table, tbody { display: block; min-width: 0; }
  tr:has(> th) { display: none; }
  tr { display: block; margin-bottom: 10px; padding: 6px 0; background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); }
  td, tr:last-child td { display: grid; grid-template-columns: 6.5rem minmax(0, 1fr); gap: 12px; padding: 6px 16px; border: 0; }
  td::before { content: attr(data-label); padding-top: 2px; font: 600 11px/1.4 Inter, sans-serif; letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
}
@media (max-width: 420px) {
  .actions .btn { flex: 1 1 auto; justify-content: center; }
  .sections a { padding: 9px 11px; }
  .finder { padding: 14px; }
}

/* One entrance, only when the reader allows motion. */
@media (prefers-reduced-motion: no-preference) {
  .hero > * { animation: rise .5s ease both; }
  .hero > *:nth-child(2) { animation-delay: .08s; }
  @keyframes rise { from { opacity: 0; transform: translateY(8px); } }
}
@media (prefers-reduced-motion: reduce) {
  html { scroll-behavior: auto; }
  .btn, .card, .tag, .search { transition: none; }
}
"

/// The citation. CITATION.cff at the repository root has the same data.
const cite_apa =
  "h0ffmann. (2026). skills [Computer software]. https://github.com/piabrota/skills"

const cite_bibtex =
  "@software{h0ffmann_skills_2026,
  author = {h0ffmann},
  title = {skills},
  year = {2026},
  url = {https://github.com/piabrota/skills},
  license = {MPL-2.0},
  note = {ORCID 0009-0009-1056-7661}
}"

const github_icon =
  "<svg aria-hidden='true' viewBox='0 0 16 16' width='16' height='16'><path d='M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z'/></svg>"

const star_icon =
  "<svg aria-hidden='true' viewBox='0 0 16 16' width='16' height='16'><path d='M8 .25a.75.75 0 0 1 .673.418l1.882 3.815 4.21.612a.75.75 0 0 1 .416 1.279l-3.046 2.97.719 4.192a.751.751 0 0 1-1.088.791L8 12.347l-3.766 1.98a.75.75 0 0 1-1.088-.79l.72-4.194L.818 6.374a.75.75 0 0 1 .416-1.28l4.21-.611L7.327.668A.75.75 0 0 1 8 .25Zm0 2.445L6.615 5.5a.75.75 0 0 1-.564.41l-3.097.45 2.24 2.184a.75.75 0 0 1 .216.664l-.528 3.084 2.769-1.456a.75.75 0 0 1 .698 0l2.77 1.456-.53-3.084a.75.75 0 0 1 .216-.664l2.24-2.183-3.096-.45a.75.75 0 0 1-.564-.41L8 2.694Z'/></svg>"

const cite_icon =
  "<svg aria-hidden='true' viewBox='0 0 16 16' width='16' height='16'><path d='M1.75 2.5h10.5a.75.75 0 0 1 0 1.5H1.75a.75.75 0 0 1 0-1.5Zm4 5h8.5a.75.75 0 0 1 0 1.5h-8.5a.75.75 0 0 1 0-1.5Zm0 5h8.5a.75.75 0 0 1 0 1.5h-8.5a.75.75 0 0 1 0-1.5ZM2.5 7.75v6a.75.75 0 0 1-1.5 0v-6a.75.75 0 0 1 1.5 0Z'/></svg>"

/// The org's mark, as the site draws it: an open green eye on red.
const eye =
  "<svg class='eye' viewBox='0 0 100 100' width='30' height='30' aria-hidden='true'><rect width='100' height='100' rx='22' fill='#BC2318'/><path d='M12 50 Q50 18 88 50 Q50 82 12 50Z' fill='#F7F3EA'/><circle cx='50' cy='50' r='14' fill='#2E9E4F'/><circle cx='50' cy='50' r='6' fill='#0B0D12'/></svg>"

/// Shows the star count from the GitHub API, if it answers, and copies a command or the
/// citation. A copy that the browser refuses says so. The page works without it.
const header_script =
  "<script>
(() => {
  fetch('https://api.github.com/repos/piabrota/skills')
    .then(r => r.ok ? r.json() : null)
    .then(d => { if (d && typeof d.stargazers_count === 'number') document.getElementById('stars').textContent = d.stargazers_count; })
    .catch(() => {});
  const say = (b, text) => { b.textContent = text; setTimeout(() => { b.textContent = 'Copy'; }, 1500); };
  for (const b of document.querySelectorAll('button[data-copy]')) {
    b.addEventListener('click', () => {
      Promise.resolve()
        .then(() => navigator.clipboard.writeText(document.getElementById(b.dataset.copy).textContent))
        .then(() => say(b, 'Copied'), () => say(b, 'Copy failed'));
    });
  }
})();
</script>
"

/// The frame of every page: the head, the bar with the brand, the way back to the site, the
/// sections, then the page's hero and main, and the foot.
fn page(title: String, current: String, hero: String, main: String) -> String {
  "<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>" <> escape(title) <> "</title>
<meta name='theme-color' content='#0B0D12' media='(prefers-color-scheme: dark)'>
<meta name='theme-color' content='#FFFFFF' media='(prefers-color-scheme: light)'>
<link rel='icon' href='data:,'>
<link rel='preconnect' href='https://fonts.googleapis.com'>
<link rel='preconnect' href='https://fonts.gstatic.com' crossorigin>
<link rel='stylesheet' href='https://fonts.googleapis.com/css2?family=Fjalla+One&amp;family=Inter:wght@400;600&amp;family=JetBrains+Mono&amp;display=swap'>
<style>" <> style <> "</style>
</head>
<body>
<a class='skip' href='#main'>Skip to the content</a>
<header class='top'>
<div class='wrap bar'>
<a class='brand' href='" <> home_url <> "' title='Back to piabrota.art'>" <> eye <> "<span translate='no'>piabrota</span></a>
<nav class='sections' aria-label='Sections'>" <> nav_link(
    current,
    "skills",
    "index.html",
  ) <> nav_link(current, "agents", "agents.html") <> nav_link(
    current,
    "awesome-skills",
    "awesome-skills.html",
  ) <> "</nav>
</div>
" <> hero <> "</header>
<main id='main'>
" <> main <> "</main>
" <> foot() <> header_script <> "</body>
</html>
"
}

fn nav_link(current: String, name: String, href: String) -> String {
  let here = case current == name {
    True -> " aria-current='page'"
    False -> ""
  }
  "<a href='" <> href <> "'" <> here <> ">" <> name <> "</a>"
}

/// The hero: an eyebrow (already HTML), the title with its muted second half, the lede, what
/// goes below the lede, and a drawing beside it.
fn hero(
  eyebrow: String,
  title: String,
  muted: String,
  lede: String,
  below: String,
  drawing: String,
) -> String {
  "<div class='wrap hero'>
<div>
" <> eyebrow <> "
<h1>" <> title <> case muted {
    "" -> ""
    _ -> " <span>" <> muted <> "</span>"
  } <> "</h1>
" <> case lede {
    "" -> ""
    _ -> "<p class='lede'>" <> lede <> "</p>\n"
  } <> below <> "</div>
" <> drawing <> "</div>
"
}

/// The way back, as the eyebrow of a page inside the site: each step is a link.
fn crumbs(trail: List(#(String, String))) -> String {
  "<nav class='eyebrow' aria-label='Breadcrumb'>"
  <> string.join(
    list.map(trail, fn(step) {
      let #(label, href) = step
      "<a href='" <> href <> "'>" <> escape(label) <> "</a>"
    }),
    " · ",
  )
  <> "</nav>"
}

fn button(href: String, label: String, primary: Bool) -> String {
  let class = case primary {
    True -> "btn primary"
    False -> "btn"
  }
  "<a class='" <> class <> "' href='" <> escape(href) <> "'>" <> label <> "</a>"
}

fn foot() -> String {
  "<footer class='foot'>
<div class='wrap foot-in'>
<p>Built with Gleam on Erlang/OTP: plain HTML and CSS, and a small script for the search. <a href='https://github.com/piabrota/nix-os'>nix-os</a> builds and serves it.</p>
<p>Content by <a href='https://github.com/h0ffmann'>h0ffmann</a>, MPL-2.0.</p>
<nav class='orgs' aria-label='Organizations'><a href='https://github.com/marola-dev'>marola-dev</a> · <a href='" <> home_url <> "'>piabrota.art</a> · <a href='https://github.com/ouroboric-dev'>ouroboric-dev</a></nav>
<div class='actions small'>
<a class='btn' href='" <> repo_url <> "' title='Star piabrota/skills on GitHub'>" <> github_icon <> " " <> star_icon <> " Star <span class='stars' id='stars'></span></a>
<details class='cite'><summary class='btn'>" <> cite_icon <> " Cite</summary>
<div class='cite-box'>
" <> terminal("APA", "apa", "", cite_apa) <> terminal(
    "BibTeX",
    "bibtex",
    "",
    cite_bibtex,
  ) <> "<p>Source: <a href='" <> repo_url <> "/blob/main/CITATION.cff'>CITATION.cff</a></p>
</div>
</details>
</div>
</div>
</footer>
"
}

/// A command, or a text to copy, as a terminal card: the title and the copy button in the bar.
/// `class` is `sh` for a prompt that CSS draws (it is not in the text that the button copies).
fn terminal(title: String, id: String, class: String, text: String) -> String {
  "<div class='terminal'><div class='term-bar'><span class='dots' aria-hidden='true'><i></i><i></i><i></i></span><span class='term-title'>"
  <> title
  <> "</span><button type='button' class='btn copy' data-copy='"
  <> id
  <> "' aria-describedby='"
  <> id
  <> "'>Copy</button></div><pre translate='no' class='"
  <> class
  <> "' id='"
  <> id
  <> "'>"
  <> escape(text)
  <> "</pre></div>
"
}

/// A file, as a terminal card with no button.
fn doc_terminal(title: String, text: String) -> String {
  "<div class='terminal'><div class='term-bar'><span class='dots' aria-hidden='true'><i></i><i></i><i></i></span><span class='term-title'>"
  <> title
  <> "</span></div><pre class='doc'>"
  <> escape(text)
  <> "</pre></div>
"
}

fn section_head(title: String, note: String) -> String {
  "<div class='section-head'><h2>"
  <> title
  <> "</h2><span class='source'>"
  <> note
  <> "</span></div>
"
}

fn tag_link(tag: String) -> String {
  "<a class='tag' href='index.html?tag="
  <> escape(tag)
  <> "'>"
  <> escape(tag)
  <> "</a>"
}

/// The brush drawing of 技 for the hero: waza.svg without its own colours, so that CSS paints
/// the strokes in the accent. The file itself is still written, as it was.
fn inline_logo(svg: String) -> String {
  let svg = string.replace(svg, "<svg ", "<svg class='kanji' ")
  case string.split_once(svg, "<style>") {
    Ok(#(before, rest)) ->
      case string.split_once(rest, "</style>") {
        Ok(#(_, after)) -> before <> after
        Error(_) -> svg
      }
    Error(_) -> svg
  }
}

fn index_page(
  skills: List(Skill),
  common: List(Skill),
  logo: String,
) -> String {
  let all = list.append(skills, common)
  let groups = list.chunk(all, fn(s) { s.category })
  let own_categories = list.length(list.chunk(skills, fn(s) { s.category }))
  let anchors =
    list.map(groups, fn(group) {
      let assert [first, ..] = group
      "<a href='#"
      <> first.category
      <> "'>"
      <> escape(first.category)
      <> " <span>"
      <> int.to_string(list.length(group))
      <> "</span></a>"
    })
  let tag_counts =
    all
    |> list.flat_map(fn(s) { s.tags })
    |> list.sort(string.compare)
    |> list.chunk(fn(t) { t })
    |> list.map(fn(same) {
      let assert [tag, ..] = same
      "<a class='tag' data-tag='"
      <> escape(tag)
      <> "' href='?tag="
      <> escape(tag)
      <> "'>"
      <> escape(tag)
      <> " <span class='n'>"
      <> int.to_string(list.length(same))
      <> "</span></a>"
    })
  let lede =
    "A skill is one folder with a <code>SKILL.md</code> file. A skill with the tag <code>manual</code> runs only when you call it by name.
<a href='awesome-skills.html'>awesome-skills</a> lists other skill collections.
<a href='agents.html'>agents</a> is the separate index of the Claude agents."
  let metrics =
    "<dl class='metrics'>"
    <> metric("skills", list.length(skills))
    <> metric("categories", own_categories)
    <> metric("from other authors", list.length(common))
    <> "</dl>
"
  let below =
    metrics
    <> "<div class='actions'>"
    <> button("#install", "Install ↓", True)
    <> button("#skills", "Find a skill ↓", False)
    <> button(repo_url, "piabrota/skills ↗", False)
    <> "</div>
"
  let drawing =
    "<figure class='drawing'>"
    <> inline_logo(logo)
    <> "<figcaption>waza · skill</figcaption></figure>
"
  page(
    "skills",
    "skills",
    hero(
      "<p class='eyebrow'>piabrota.art · skills</p>",
      "skills",
      "· for agents",
      lede,
      below,
      drawing,
    ),
    "<nav class='anchors' aria-label='Categories'><div class='wrap'>"
      <> string.join(anchors, "\n")
      <> "</div></nav>
<section class='wrap' id='install'>
"
      <> section_head("Install", "plugin waza")
      <> "<p class='sub'>One command installs the plugin with all the skills. Claude Code 2.1.275 or newer adds the marketplace in the same step.</p>
<div class='installs'>
"
      <> terminal(
      "in a claude code session",
      "install-session",
      "",
      "/plugin install waza --marketplace piabrota/skills",
    )
      <> terminal(
      "in a terminal",
      "install-shell",
      "sh",
      "claude plugin install waza --marketplace piabrota/skills",
    )
      <> "</div>
</section>
<section class='wrap' id='skills'>
"
      <> section_head(
      "Skills",
      int.to_string(list.length(skills))
        <> " in the plugin, "
        <> int.to_string(list.length(common))
        <> " elsewhere",
    )
      <> "<div class='finder'>
<input id='q' class='search' type='search' name='q' autocomplete='off' spellcheck='false' placeholder='Search by name, text or tag…' aria-label='Search the skills'>
<div class='chips' id='tags'>"
      <> string.join(tag_counts, "\n")
      <> "</div>
<p class='found' id='count' aria-live='polite'></p>
</div>
<div class='empty' id='empty' hidden><p>No skill matches the search.</p><button type='button' class='btn' id='clear'>Clear the search</button></div>
"
      <> string.concat(list.map(groups, lane))
      <> "</section>
"
      <> search_script,
  )
}

fn metric(label: String, n: Int) -> String {
  "<div><dt>" <> label <> "</dt><dd>" <> int.to_string(n) <> "</dd></div>"
}

/// One category: its name and count, then a card for each skill.
fn lane(group: List(Skill)) -> String {
  let assert [first, ..] = group
  "<div class='lane' id='" <> first.category <> "'>
<h3>" <> escape(first.category) <> " <span class='count'>" <> int.to_string(
    list.length(group),
  ) <> "</span></h3>
" <> case first.category {
    "elsewhere" -> elsewhere_note
    _ -> ""
  } <> "<ul class='cards'>
" <> string.concat(list.map(group, card)) <> "</ul>
</div>
"
}

/// Filters the cards: each word of the search must occur in the name, the text or the tags,
/// and a selected tag must be one of the tags. A lane with no card left is hidden; with no
/// card at all, the empty box shows and its button clears the search.
const search_script =
  "<script>
(() => {
  const q = document.getElementById('q');
  const count = document.getElementById('count');
  const empty = document.getElementById('empty');
  let tag = new URLSearchParams(location.search).get('tag') || '';
  const cards = [...document.querySelectorAll('[data-tags]')];
  const lanes = [...document.querySelectorAll('.lane')];
  function run() {
    const words = q.value.toLowerCase().split(/\\s+/).filter(Boolean);
    let shown = 0;
    for (const c of cards) {
      const tags = c.dataset.tags.split(' ');
      const text = c.textContent.toLowerCase();
      const ok = (!tag || tags.includes(tag)) && words.every(w => text.includes(w));
      c.hidden = !ok;
      if (ok) shown++;
    }
    for (const l of lanes) {
      const n = l.querySelectorAll('[data-tags]:not([hidden])').length;
      l.hidden = n === 0;
      l.querySelector('.count').textContent = n;
    }
    for (const a of document.querySelectorAll('#tags .tag')) {
      const on = a.dataset.tag === tag;
      a.classList.toggle('on', on);
      if (on) a.setAttribute('aria-current', 'true'); else a.removeAttribute('aria-current');
    }
    count.textContent = (tag || words.length) ? shown + ' of ' + cards.length + ' skills' + (tag ? ' with tag ' + tag : '') : '';
    empty.hidden = shown !== 0;
  }
  for (const a of document.querySelectorAll('#tags .tag')) {
    a.addEventListener('click', e => {
      e.preventDefault();
      tag = tag === a.dataset.tag ? '' : a.dataset.tag;
      history.replaceState(null, '', tag ? '?tag=' + encodeURIComponent(tag) : location.pathname);
      run();
    });
  }
  document.getElementById('clear').addEventListener('click', () => {
    q.value = '';
    tag = '';
    history.replaceState(null, '', location.pathname);
    run();
    q.focus();
  });
  q.addEventListener('input', run);
  run();
})();
</script>
"

const elsewhere_note =
  "<p class='sub'>Skills of other authors that these projects use. They are not in the plugin.
<a href=\""
  <> repo_url
  <> "/blob/main/docs/common-skills.md\">common-skills</a> gives the licence and the install command of each.</p>
"

fn card(s: Skill) -> String {
  let #(href, mark) = case s.url {
    "" -> #(s.name <> ".html", "")
    url -> #(url, " <span aria-hidden='true'>↗</span>")
  }
  "<li class='card' data-tags='" <> escape(string.join(s.tags, " ")) <> "'>
<h4 class='card-name'><a href='" <> escape(href) <> "'>" <> escape(s.name) <> mark <> "</a></h4>
<p class='desc'>" <> escape(s.description) <> "</p>
<p class='card-tags'>" <> string.concat(list.map(s.tags, tag_link)) <> "</p>
</li>
"
}

fn skill_page(
  s: Skill,
  prev: Result(Skill, Nil),
  next: Result(Skill, Nil),
) -> String {
  let step = fn(neighbour: Result(Skill, Nil), arrow_first: Bool) {
    case neighbour {
      Ok(n) ->
        case arrow_first {
          True ->
            "<a class='btn' href='"
            <> n.name
            <> ".html'><span aria-hidden='true'>←</span> "
            <> escape(n.name)
            <> "</a>"
          False ->
            "<a class='btn' href='"
            <> n.name
            <> ".html'>"
            <> escape(n.name)
            <> " <span aria-hidden='true'>→</span></a>"
        }
      Error(_) -> "<span></span>"
    }
  }
  let file = "skills/" <> s.category <> "/" <> s.name <> "/SKILL.md"
  page(
    s.name <> " · skills",
    "skills",
    hero(
      crumbs([
        #("piabrota.art", home_url),
        #("skills", "index.html"),
        #(s.category, "index.html#" <> s.category),
      ]),
      escape(s.name),
      "· " <> escape(s.category),
      escape(s.description),
      "<p class='chips'>" <> string.concat(list.map(s.tags, tag_link)) <> "</p>
<div class='actions'>" <> button(
        repo_url <> "/blob/main/" <> file,
        "SKILL.md on GitHub ↗",
        True,
      ) <> button("index.html#" <> s.category, "← Back to all skills", False) <> "</div>
",
      "",
    ),
    "<section class='wrap'>
" <> section_head("SKILL.md", escape(file)) <> doc_terminal("SKILL.md", s.body) <> "</section>
<nav class='wrap pager' aria-label='Neighbouring skills'>" <> step(prev, True) <> step(
      next,
      False,
    ) <> "</nav>
",
  )
}

/// Writes the table of `docs/awesome-skills.md` as HTML. A row is
/// `| n | [owner/repo](url) | stars | text |`.
fn awesome_page() -> String {
  let assert Ok(text) = read(awesome_md)
  let intro = case string.split_once(text, "\n\n") {
    Ok(#(_, rest)) ->
      case string.split_once(rest, "\n\n") {
        Ok(#(intro, _)) -> intro
        Error(_) -> ""
      }
    Error(_) -> ""
  }
  let rows =
    text
    |> string.split("\n")
    |> list.filter_map(awesome_row)
  page(
    "awesome-skills · skills",
    "awesome-skills",
    hero(
      crumbs([#("piabrota.art", home_url), #("skills", "index.html")]),
      "awesome-skills",
      "· other collections",
      escape(intro),
      "<div class='actions'>"
        <> button("index.html", "← Back to all skills", False)
        <> "</div>
",
      "",
    ),
    "<section class='wrap'>
<div class='scroll' tabindex='0'><table>
<tr><th>#</th><th>Repository</th><th>Stars</th><th>What it is</th></tr>
" <> string.concat(rows) <> "</table></div>
</section>
",
  )
}

fn awesome_row(line: String) -> Result(String, Nil) {
  case string.split(line, " | ") {
    ["| " <> n, repo, stars, what] -> {
      use _ <- result.try(int.parse(n))
      use #(name, url) <- result.try(string.split_once(repo, "]("))
      let name = string.drop_start(name, 1)
      let url = string.drop_end(url, 1)
      let what = what |> string.drop_end(2) |> string.replace("`", "")
      Ok(
        "<tr><td data-label=\"#\">"
        <> n
        <> "</td><td data-label=\"Repository\"><a href=\""
        <> escape(url)
        <> "\">"
        <> escape(name)
        <> "</a></td><td data-label=\"Stars\">"
        <> escape(stars)
        <> "</td><td data-label=\"What it is\">"
        <> escape(what)
        <> "</td></tr>\n",
      )
    }
    _ -> Error(Nil)
  }
}

/// The agent files in `agents/`: each one is a Claude Code subagent, copied as
/// is. `README.md` is the index, not an agent.
fn load_agents() -> List(Skill) {
  list_dir(agents_dir)
  |> list.filter(fn(f) { string.ends_with(f, ".md") && f != "README.md" })
  |> list.sort(string.compare)
  |> list.filter_map(fn(f) {
    let name = string.drop_end(f, 3)
    use text <- result.try(read(agents_dir <> "/" <> f))
    Ok(parse("agents", name, text))
  })
}

/// The agents index: `agents/README.md` as HTML. A link to an agent file goes
/// to the page of that agent.
fn agents_page() -> String {
  let assert Ok(text) = read(agents_dir <> "/README.md")
  let #(title, rest) = case string.split_once(text, "\n\n") {
    Ok(#("# " <> title, rest)) -> #(title, rest)
    _ -> #("agents", text)
  }
  page(
    "agents · skills",
    "agents",
    hero(
      crumbs([#("piabrota.art", home_url), #("skills", "index.html")]),
      escape(title),
      "· for Claude",
      "",
      "<div class='actions'>"
        <> button(
        repo_url <> "/blob/main/agents/README.md",
        "agents/README.md on GitHub ↗",
        True,
      )
        <> button("index.html", "← Back to all skills", False)
        <> "</div>
",
      "",
    ),
    "<section class='wrap prose'>\n" <> markdown(rest) <> "</section>\n",
  )
}

fn agent_page(a: Skill) -> String {
  page(
    a.name <> " · agents",
    "agents",
    hero(
      crumbs([
        #("piabrota.art", home_url),
        #("skills", "index.html"),
        #("agents", "agents.html"),
      ]),
      escape(a.name),
      "· agent",
      escape(a.description),
      "<div class='actions'>"
        <> button(
        repo_url <> "/blob/main/agents/" <> a.name <> ".md",
        "The file on GitHub ↗",
        True,
      )
        <> button("agents.html", "← Back to all agents", False)
        <> "</div>
",
      "",
    ),
    "<section class='wrap'>
" <> section_head("The file", escape("agents/" <> a.name <> ".md")) <> doc_terminal(
      a.name <> ".md",
      a.body,
    ) <> "</section>
",
  )
}

/// A small Markdown to HTML step for the agents index: headings, paragraphs,
/// lists, tables, inline code and links. Nothing more is necessary there.
fn markdown(text: String) -> String {
  text
  |> string.split("\n\n")
  |> list.map(block)
  |> string.concat
}

fn block(b: String) -> String {
  let lines =
    b
    |> string.trim
    |> string.split("\n")
  case lines {
    [""] -> ""
    ["# " <> h] -> "<h1>" <> inline(h) <> "</h1>\n"
    ["## " <> h] -> "<h2>" <> inline(h) <> "</h2>\n"
    ["| " <> _, ..] -> table(lines)
    ["- " <> _, ..] ->
      "<ul>"
      <> string.concat(
        list.map(lines, fn(l) {
          "<li>" <> inline(string.drop_start(l, 2)) <> "</li>"
        }),
      )
      <> "</ul>\n"
    _ -> "<p>" <> inline(string.join(lines, " ")) <> "</p>\n"
  }
}

fn table(lines: List(String)) -> String {
  let rows =
    lines
    |> list.filter(fn(l) { !string.starts_with(l, "|---") })
    |> list.map(fn(l) {
      l
      |> string.drop_start(2)
      |> string.drop_end(2)
      |> string.split(" | ")
    })
  case rows {
    [head, ..body] ->
      "<div class=\"scroll\" tabindex=\"0\"><table>\n<tr>"
      <> string.concat(list.map(head, fn(c) { "<th>" <> inline(c) <> "</th>" }))
      <> "</tr>\n"
      <> string.concat(
        list.map(body, fn(r) {
          "<tr>"
          <> string.concat(
            list.index_map(r, fn(c, i) {
              let label = case list.drop(head, i) {
                [label, ..] -> label
                [] -> ""
              }
              "<td data-label=\""
              <> escape(label)
              <> "\">"
              <> inline(c)
              <> "</td>"
            }),
          )
          <> "</tr>\n"
        }),
      )
      <> "</table></div>\n"
    [] -> ""
  }
}

/// Links first, then code spans and escapes in the text around them.
fn inline(s: String) -> String {
  case string.split_once(s, "[") {
    Error(_) -> code(s)
    Ok(#(before, rest)) ->
      case string.split_once(rest, "](") {
        Ok(#(label, rest2)) ->
          case string.contains(label, "]"), string.split_once(rest2, ")") {
            False, Ok(#(url, after)) ->
              code(before)
              <> "<a href=\""
              <> escape(agent_link(url))
              <> "\">"
              <> code(label)
              <> "</a>"
              <> inline(after)
            _, _ -> code(before) <> "[" <> inline(rest)
          }
        Error(_) -> code(before) <> "[" <> inline(rest)
      }
  }
}

/// A link to an agent file in the same folder goes to the page of that agent.
fn agent_link(url: String) -> String {
  case string.contains(url, "/"), string.ends_with(url, ".md") {
    False, True -> "agent-" <> string.drop_end(url, 3) <> ".html"
    _, _ -> url
  }
}

fn code(s: String) -> String {
  s
  |> string.split("`")
  |> list.index_map(fn(part, i) {
    case i % 2 {
      1 -> "<code>" <> escape(part) <> "</code>"
      _ -> escape(part)
    }
  })
  |> string.concat
}
