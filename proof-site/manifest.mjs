// The list of pages of a built site, as JSON: what index.mjs draws the index from. The build runs it
// on `dist` after the brand bar is in. For each .html page it reads the <title>, the lang of the
// <html> tag and whether archify drew it.
//
//   node manifest.mjs <dist> <proof|pirsig> > manifest.json
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

/** Text of an HTML title as plain text: entities decoded, white space folded. */
export function decode(text) {
  return text
    .replace(/&(?:#(\d+)|#x([0-9a-f]+)|([a-z]+));/gi, (m, dec, hex, name) => {
      if (dec) return String.fromCodePoint(Number(dec));
      if (hex) return String.fromCodePoint(parseInt(hex, 16));
      return ENTITIES[name.toLowerCase()] ?? m;
    })
    .replace(/\s+/g, ' ')
    .trim();
}

/** The <title> of a page, or '' when it has none. */
export function titleOf(html) {
  const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  return m ? decode(m[1]) : '';
}

/** The lang of the <html> tag; `en` when it has none. */
export function langOf(html) {
  const m = /<html\b[^>]*\blang=["']?([A-Za-z-]+)/i.exec(html);
  return m ? m[1] : 'en';
}

/**
 * The group of a page: the first folder under proof/ (docs/<name> for a page of docs/), or the first
 * folder of a pirsig page. A page that sits at the top of its tree has the group ''.
 */
export function groupOf(site, path) {
  const parts = path.split('/');
  if (site === 'proof') parts.shift();
  parts.pop();
  if (site === 'proof' && parts[0] === 'docs') return parts.slice(0, 2).join('/');
  return parts[0] ?? '';
}

const capital = (s) => s.charAt(0).toUpperCase() + s.slice(1);

/** The readable title of a group: the title of the folder's own index (before a colon), else its name. */
export function groupTitle(group, indexTitle) {
  const own = indexTitle.replace(/ · proof$/, '').split(': ')[0];
  return own || capital(group.split('/').pop().replace(/-/g, ' '));
}

export function scan(dist, site) {
  const files = readdirSync(dist, { recursive: true, withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith('.html'))
    .map((e) => relative(dist, join(e.parentPath, e.name)).split(sep).join('/'))
    .filter((p) => p !== 'index.html')
    .sort();
  const pages = files.map((path) => {
    const html = readFileSync(join(dist, path), 'utf8');
    const diagram = html.includes('archify-theme');
    return {
      path,
      href: diagram ? `${path}?theme=dark` : path,
      title: titleOf(html) || path,
      group: groupOf(site, path),
      lang: langOf(html),
      kind: diagram ? 'diagram' : 'page',
    };
  });
  const groups = {};
  for (const p of pages) {
    if (p.kind !== 'page' || !p.group || p.group in groups) continue;
    const own = pages.find((q) => q.path === `${site === 'proof' ? 'proof/' : ''}${p.group}/index.html`);
    groups[p.group] = groupTitle(p.group, own ? own.title : '');
  }
  // `N vídeo(s) indexado(s)`, said by the page of the video notes; null when it does not say.
  const videos = pages.find((p) => p.path === 'videos/index.html');
  const said = videos && /(\d+) vídeos? indexados?/.exec(readFileSync(join(dist, videos.path), 'utf8'));
  return { site, pages, groups, videos: said ? Number(said[1]) : null };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [dist, site] = process.argv.slice(2);
  process.stdout.write(`${JSON.stringify(scan(dist, site), null, 1)}\n`);
}
