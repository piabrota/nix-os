// A build step: put the brand bar (design/kit.mjs, chrome with `bar`) into every .html file of a
// folder that came from another repository. It adds one element and one <style> right after the
// opening <body> tag, and touches nothing else: not the page's CSS, not its scripts, not its text.
// Every selector of the bar's CSS holds the class .pb-chrome, so no rule of the page reaches the bar
// and none of the bar's reaches the page. The marker `data-pb-chrome` makes a second run a no-op.
//
//   node design/inject.mjs inject <dir> --current <id> --sites <sites.json> [--index <href>]
//   node design/inject.mjs check <dir> [--except <relative path>]...
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chrome, css } from './kit.mjs';

export const MARKER = 'data-pb-chrome';

// An archify page puts its toolbar at the top with `position: absolute` above 720 px, so the bar would
// sit under it. This rule moves the toolbar down by the bar's height (44 px and its two margins) on a
// page that has the bar, and not in presentation or embed mode, where the bar is hidden. It holds the
// bar's class in its selector and sets the toolbar's margin only: nothing of the page's CSS changes.
const ARCHIFY_TOOLBAR = '@media (min-width: 721px) { html:not([data-embed="true"]):not([data-present="true"]) .pb-chrome--bar ~ .toolbar { margin-top: 68px; } }';

const noComments = (text) => text.replace(/\/\*[\s\S]*?\*\//g, '');

/** The bar's CSS: the dark tokens declared on the bar itself (so it is dark in any theme), then chrome.css. */
export function barStyle(html = '') {
  const dark = /:root\s*\{([^}]*)\}/.exec(css('tokens'))[1]
    .split(';')
    .map((d) => d.trim())
    .filter((d) => d.startsWith('--'))
    .join(';');
  const rules = `.pb-chrome--bar{${dark}}\n${noComments(css('chrome')).replace(/\n\s*/g, ' ').trim()}`;
  return html.includes('archify-theme') ? `${rules}\n${ARCHIFY_TOOLBAR}` : rules;
}

/** The HTML with the bar after its <body> tag. Throws when it has no <body>. */
export function injectHtml(html, { current, sites, index }, name = 'page') {
  if (html.includes(MARKER)) return html;
  // The <body> that follows </head>; else the first one. A script string cannot fool the first form.
  const m = /<\/head>(?:\s|<!--[\s\S]*?-->)*<body\b[^>]*>/i.exec(html) ?? /<body\b[^>]*>/i.exec(html);
  if (!m) throw new Error(`${name}: no <body> tag, so the brand bar has no place to go`);
  const at = m.index + m[0].length;
  return `${html.slice(0, at)}<style>${barStyle(html)}</style>${chrome({ current, sites, index, bar: true })}${html.slice(at)}`;
}

/** Every .html file under a folder, as paths, sorted. */
export function htmlFiles(dir) {
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.html'))
    .map((e) => join(e.parentPath, e.name))
    .sort();
}

/** Put the bar into every .html file of a folder. Returns how many files it changed. */
export function injectDir({ dir, current, sites, index }) {
  let changed = 0;
  for (const file of htmlFiles(dir)) {
    const before = readFileSync(file, 'utf8');
    const after = injectHtml(before, { current, sites, index }, relative(dir, file));
    if (after !== before) {
      writeFileSync(file, after);
      changed += 1;
    }
  }
  return changed;
}

/** The .html files of a folder with no bar, except the paths (relative to the folder) in `except`. */
export function withoutBar(dir, except = []) {
  return htmlFiles(dir)
    .map((f) => relative(dir, f))
    .filter((f) => !except.includes(f))
    .filter((f) => !readFileSync(join(dir, f), 'utf8').includes(MARKER));
}

function flags(args) {
  const out = {};
  for (let i = 0; i < args.length; i += 2) (out[args[i].replace(/^--/, '')] ??= []).push(args[i + 1]);
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [cmd, dir, ...rest] = process.argv.slice(2);
  const f = flags(rest);
  try {
    if (cmd === 'inject') {
      const sites = JSON.parse(readFileSync(f.sites[0], 'utf8'));
      const n = injectDir({ dir, current: f.current[0], sites, index: f.index?.[0] ?? null });
      console.error(`brand bar: ${n} of ${htmlFiles(dir).length} pages changed in ${dir}`);
    } else if (cmd === 'check') {
      const except = f.except ?? [];
      const bad = withoutBar(dir, except);
      if (bad.length) throw new Error(`no brand bar in: ${bad.join(', ')}`);
      console.error(`brand bar: every page of ${dir} has it, except ${except.join(', ') || 'none'}`);
    } else {
      throw new Error('usage: inject.mjs inject|check <dir> ...');
    }
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
}
