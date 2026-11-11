// The index of proof.piabrota.art and of pirsig.piabrota.art, made with the design kit from the
// manifest that manifest.mjs wrote (docs/DESIGN-KIT.md). The page loads no script.
//
//   node index.mjs <proof|pirsig> <manifest.json> --rev <commit> --sites <sites.json> --icons <html> [--loc <loc.json>] > index.html
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { card, cardGrid, chrome, footer, hero, main, page, section, sub, top, url } from '../design/kit.mjs';

const MODULES = ['chrome', 'hero', 'section', 'cards', 'pills', 'footer'];

const base = (lang) => lang.split('-')[0].toLowerCase();
const langName = { en: 'English', pt: 'Português (BR)' };
const langPill = (lang) => base(lang).toUpperCase();

// The drawings beside the heroes, in the red of --accent-text: proof's ∀, and pirsig's net of notes.
const FOR_ALL = '<svg viewBox="0 0 100 100"><g fill="none" stroke="var(--accent-text)" stroke-linecap="round" stroke-linejoin="round" stroke-width="7"><path d="M18 18 L50 86 L82 18"></path><path d="M32 52 H68"></path></g></svg>';
const NOTE_NET = '<svg viewBox="0 0 100 100"><g fill="none" stroke="var(--accent-text)" stroke-linecap="round" stroke-linejoin="round" stroke-width="4"><path d="M24 30 L52 20 L78 40 L64 76 L30 70 Z M52 20 L64 76 M24 30 L64 76 M30 70 L78 40"></path></g><g fill="var(--accent-text)"><circle cx="24" cy="30" r="7"></circle><circle cx="52" cy="20" r="7"></circle><circle cx="78" cy="40" r="7"></circle><circle cx="64" cy="76" r="7"></circle><circle cx="30" cy="70" r="7"></circle></g></svg>';

/** A page's title as a card shows it: without the site's suffix, and without archify's "Diagram" word. */
export function cleanTitle(p) {
  const t = p.title.replace(/ · proof$/, '');
  return p.kind === 'diagram' ? t.replace(/ Diagram$/, '').replace(/^Diagrama /, '') : t;
}

// An archify title reads "Name: what it says" (figures-site does the same): the card shows the two parts.
const pageCard = (p, { pills = [], line } = {}) => {
  const title = cleanTitle(p);
  const at = p.kind === 'diagram' ? title.indexOf(': ') : -1;
  return card({
    title: at < 0 ? title : title.slice(0, at),
    line: at < 0 ? line : title.slice(at + 2),
    foot: `/${p.path}`,
    href: p.href,
    pills,
  });
};

function diagramGrids(diagrams) {
  const langs = [...new Set(diagrams.map((p) => base(p.lang)))].sort((a, b) => (a === 'en' ? -1 : b === 'en' ? 1 : a.localeCompare(b)));
  return langs
    .map((l) => sub(langName[l] ?? l) + cardGrid(diagrams.filter((p) => base(p.lang) === l).map((p) => pageCard(p, { pills: [langPill(p.lang)] }))))
    .join('');
}

// Lines of code as the hero shows them: 2,475.
const thousands = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');

/** The hero's numbers of lines of code, from loc.mjs's JSON; none without it. */
export function locStats(loc) {
  return loc ? ['lean', 'agda', 'z3'].filter((id) => loc[id]).map((id) => ({ value: thousands(loc[id].lines), label: `lines of ${loc[id].label}` })) : [];
}

export function proofIndex({ pages, groups }, { rev, sites, icons, loc }) {
  const short = rev.slice(0, 7);
  const own = pages.find((p) => p.path === 'proof/index.html');
  const diagramIndex = pages.find((p) => p.kind === 'page' && p.group === 'docs/diagrams');
  const diagrams = pages.filter((p) => p.kind === 'diagram');
  const plain = pages.filter((p) => p.kind === 'page' && p.group && p.group !== 'docs/diagrams');
  const languages = new Set(pages.map((p) => base(p.lang)));

  const sections = Object.keys(groups)
    .filter((g) => g !== 'docs/diagrams')
    .sort()
    .map((g) => {
      const inGroup = plain.filter((p) => p.group === g);
      const mixed = new Set(inGroup.map((p) => base(p.lang))).size > 1;
      return section({
        id: g.replace(/\//g, '-'),
        title: groups[g],
        count: inGroup.length,
        note: `proof/${g}/`,
        body: cardGrid(inGroup.map((p) => pageCard(p, { pills: mixed ? [langPill(p.lang)] : [] }))),
      });
    });
  const lead = diagramIndex
    ? `<p>The diagrams are drawn by <a href="https://github.com/tt-a1i/archify" rel="noopener">archify</a> and open dark. <a href="${url(diagramIndex.href)}">One index</a> lists them in the repository's own words.</p>`
    : '';
  sections.push(section({ id: 'diagrams', title: 'Diagrams', count: diagrams.length, note: 'proof/docs/diagrams/', body: lead + diagramGrids(diagrams) }));

  const actions = [{ label: 'h0ffmann/proof \u2197', href: 'https://github.com/h0ffmann/proof', variant: 'primary' }];
  if (own) actions.push({ label: 'Its own index', href: own.href });
  actions.push({ label: short, href: `https://github.com/h0ffmann/proof/tree/${rev}`, variant: 'mono' });

  return page({
    title: 'proof · piabrota',
    description: 'Every HTML page of h0ffmann/proof: specifications checked by a prover, Z3 reports and diagrams.',
    modules: MODULES,
    icons,
    body:
      top(
        chrome({ current: 'proof', sites }),
        hero({
          eyebrow: 'piabrota.art · proof',
          title: 'proof',
          tail: '· checked by a prover',
          lede: 'Specifications checked by a prover, implementations that follow them name for name, and data experiments with papers. Every HTML page of h0ffmann/proof, built from a pinned commit.',
          stats: [
            { value: plain.length, label: 'pages' },
            { value: diagrams.length, label: 'diagrams' },
            { value: languages.size, label: 'languages' },
            ...locStats(loc),
          ],
          actions,
          mark: FOR_ALL,
        }),
      ) +
      main(...sections) +
      footer({ sites, current: 'proof', built: `Pages of h0ffmann/proof at ${short}. Served by nix-os from /nix/store, on piabrota2.` }),
  });
}

export function pirsigIndex({ pages, videos }, { rev, sites, icons }) {
  const short = rev.slice(0, 7);
  const notes = pages.filter((p) => p.group === 'videos');
  const figures = pages.filter((p) => p.group === 'figures');
  // The page says how many videos it indexes; the card repeats it only when the page said it.
  const noteCards = notes.map((p) =>
    pageCard(p, {
      pills: [langPill(p.lang)],
      line: p.path === 'videos/index.html' && videos != null ? `${videos} ${videos === 1 ? 'vídeo indexado' : 'vídeos indexados'}` : undefined,
    }),
  );
  const stats = [];
  if (videos != null) stats.push({ value: videos, label: videos === 1 ? 'video note' : 'video notes' });
  stats.push({ value: figures.length, label: 'figures' });

  return page({
    title: 'pirsig · piabrota',
    description: 'The video notes and the archify figures of piabrota/pirsig, the second brain.',
    modules: MODULES,
    icons,
    body:
      top(
        chrome({ current: 'pirsig', sites }),
        hero({
          eyebrow: 'piabrota.art · pirsig',
          title: 'pirsig',
          tail: '· a second brain',
          lede: 'The brain: smart notes, PARA and the track record of decisions. The video notes and the figures of piabrota/pirsig, built from a pinned commit. The figures open dark.',
          stats,
          mark: NOTE_NET,
          actions: [
            { label: 'piabrota/pirsig \u2197', href: 'https://github.com/piabrota/pirsig', variant: 'primary' },
            { label: short, href: `https://github.com/piabrota/pirsig/tree/${rev}`, variant: 'mono' },
          ],
        }),
      ) +
      main(
        section({ id: 'videos', title: 'Video notes', count: notes.length, note: 'brain/Videos/', body: cardGrid(noteCards) }),
        section({ id: 'figures', title: 'Figures', count: figures.length, note: 'docs/archify/', body: cardGrid(figures.map((p) => pageCard(p, { pills: [langPill(p.lang)] }))) }),
      ) +
      footer({ sites, current: 'pirsig', built: `Pages of piabrota/pirsig at ${short}. Served by nix-os from /nix/store, on piabrota2. archify draws the figures.` }),
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [site, manifest, ...rest] = process.argv.slice(2);
  const f = Object.fromEntries(rest.reduce((acc, v, i) => (i % 2 ? acc : [...acc, [v.replace(/^--/, ''), rest[i + 1]]]), []));
  const ctx = { rev: f.rev, sites: JSON.parse(readFileSync(f.sites, 'utf8')), icons: f.icons ?? '', loc: f.loc ? JSON.parse(readFileSync(f.loc, 'utf8')) : null };
  const m = JSON.parse(readFileSync(manifest, 'utf8'));
  const html = site === 'proof' ? proofIndex(m, ctx) : site === 'pirsig' ? pirsigIndex(m, ctx) : null;
  if (html === null) throw new Error(`usage: index.mjs <proof|pirsig> <manifest.json> --rev <commit> --sites <sites.json> --icons <html>`);
  process.stdout.write(html);
}
