// The design kit of the piabrota sites (docs/DESIGN-KIT.md). Pure functions that return HTML strings.
// Every text argument is escaped. An argument that holds HTML says so: `body`, `head`, `icons` and
// the strings that cardGrid() and card() return. A link must be http(s), mailto or a relative path.
// No dependency: it runs on the builder with node alone.
import { readFileSync } from 'node:fs';

// The modules, in the order that page() inlines them (after tokens and base).
export const MODULES = ['chrome', 'hero', 'section', 'cards', 'pills', 'footer', 'prose'];

const TONES = ['ok', 'warn', 'none', 'accent'];
const FONTS = '<link href="https://fonts.googleapis.com" rel="preconnect"><link crossorigin href="https://fonts.gstatic.com" rel="preconnect"><link href="https://fonts.googleapis.com/css2?family=Fjalla+One&amp;family=Inter:wght@400;600&amp;family=JetBrains+Mono&amp;display=swap" rel="stylesheet">';

const cache = new Map();
/** The CSS of one file of design/css/, without its extension. */
export function css(name) {
  if (!cache.has(name)) cache.set(name, readFileSync(new URL(`./css/${name}.css`, import.meta.url), 'utf8'));
  return cache.get(name);
}

/** Text as HTML. */
export function esc(text) {
  return String(text ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

/** A link target as an attribute value: http(s), mailto or a relative path. */
export function url(target) {
  const s = String(target).trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(s) && !/^(https?|mailto):/i.test(s)) throw new Error(`design kit: link with a scheme that is not allowed: ${s}`);
  return esc(s);
}

const external = (target) => (/^https?:/i.test(String(target).trim()) ? ' rel="noopener"' : '');

/** The eye mark: the drawing of parts.eye (site/src/piabrota_site/parts.gleam), the only copy here. */
export function eye(size = 28) {
  return `<svg xmlns="http://www.w3.org/2000/svg" aria-hidden="true" class="pb-eye" height="${Number(size)}" viewBox="0 0 100 100" width="${Number(size)}"><rect fill="#BC2318" height="100" rx="22" width="100"></rect><path d="M12 50 Q50 18 88 50 Q50 82 12 50Z" fill="#F7F3EA"></path><circle cx="50" cy="50" fill="#2E9E4F" r="14"></circle><circle cx="50" cy="50" fill="#0B0D12" r="6"></circle></svg>`;
}

/** The sites that a nav lists: the public ones. */
export const publicSites = (sites) => sites.filter((s) => s.access === 'public');

function siteNav(sites, current, cls) {
  const links = publicSites(sites)
    .map((s) => `<a href="${url(s.url)}"${s.id === current ? ' aria-current="page"' : ''}>${esc(s.label)}</a>`)
    .join('');
  return `<nav class="${cls}" aria-label="piabrota sites">${links}</nav>`;
}

function known(sites, current) {
  if (current == null) return null;
  const site = sites.find((s) => s.id === current);
  if (!site) throw new Error(`design kit: "${current}" is not in design/sites.nix`);
  return site;
}

/**
 * The brand and the sites. `current` is the id of this site. By default it is the header of a kit
 * page (the brand, then the sites as one pill). With `bar` it is the 44 px strip that inject.mjs puts
 * into a foreign page: it carries the marker `data-pb-chrome`, and, when `index` is the address of
 * the site's index, a link back to it.
 */
export function chrome({ current, sites, index = null, bar = false }) {
  const site = known(sites, current);
  const brand = `<a class="pb-brand" href="https://www.piabrota.art/">${eye(bar ? 22 : 30)}<span>piabrota</span></a>`;
  if (!bar) {
    return `<div class="pb-chrome pb-chrome--page"><div class="pb-wrap pb-chrome__in">${brand}${siteNav(sites, current, 'pb-nav')}</div></div>`;
  }
  const back = index && site ? `<a class="pb-back" href="${url(index)}">\u2190 ${esc(site.label)} index</a>` : '';
  return `<div class="pb-chrome pb-chrome--bar" data-pb-chrome>${brand}${back}${siteNav(sites, current, 'pb-nav')}</div>`;
}

/** The top band: the glow behind whatever it holds, usually a chrome and a hero. */
export const top = (...parts) => `<header class="pb-top">${parts.join('')}</header>`;

/**
 * The hero. `stats` is a list of { value, label }; `actions` a list of { label, href, variant } with
 * the variant `primary` (the one filled button of the page) or `mono`. `mark` is the HTML of a drawing
 * (an inline SVG) that stands beside the text.
 */
export function hero({ eyebrow, title, tail, lede, stats = [], actions = [], mark = '' }) {
  const numbers = stats.length
    ? `<dl class="pb-stats">${stats.map((s) => `<div><dt>${esc(s.label)}</dt><dd>${esc(s.value)}</dd></div>`).join('')}</dl>`
    : '';
  const buttons = actions.length
    ? `<div class="pb-actions">${actions
        .map((a) => `<a class="pb-btn${['primary', 'mono'].includes(a.variant) ? ` pb-btn--${a.variant}` : ''}" href="${url(a.href)}"${external(a.href)}>${esc(a.label)}</a>`)
        .join('')}</div>`
    : '';
  const text = `${eyebrow ? `<p class="pb-eyebrow">${esc(eyebrow)}</p>` : ''}<h1 class="pb-title">${esc(title)}${tail ? ` <span class="pb-tail">${esc(tail)}</span>` : ''}</h1>${lede ? `<p class="pb-lede">${esc(lede)}</p>` : ''}${numbers}${buttons}`;
  return `<section class="pb-hero"><div class="pb-hero__text">${text}</div>${mark ? `<figure class="pb-hero__mark" aria-hidden="true">${mark}</figure>` : ''}</section>`;
}

/** The sections of a page, in a main element: their `§` numbers count inside it. */
export const main = (...sections) => `<main class="pb-main" id="main">${sections.join('')}</main>`;

/**
 * A section with a numbered `§` heading. The number is counted by CSS, never typed. `count` and
 * `note` (a mono line on the right) are optional. `body` is HTML.
 */
export function section({ id, title, count, note, body }) {
  const badge = count == null ? '' : `<span class="pb-count">${esc(count)}</span>`;
  const aside = note ? `<span class="pb-note">${esc(note)}</span>` : '';
  return `<section class="pb-section" id="${esc(id)}"><div class="pb-section__head"><div class="pb-section__lead"><h2 class="pb-section__title">${esc(title)}</h2>${badge}</div>${aside}</div><div class="pb-section__body">${body}</div></section>`;
}

/** A small heading inside a section. */
export const sub = (text) => `<h3 class="pb-sub">${esc(text)}</h3>`;

/** A state or a tag. `tone` is ok, warn, none or accent; any other value is the plain pill. */
export function pill(text, tone) {
  const t = TONES.includes(tone) ? ` pb-pill--${tone}` : tone === 'mono' ? ' pb-pill--mono' : '';
  return `<span class="pb-pill${t}">${esc(text)}</span>`;
}

/** One card. `pills` is a list of strings or { text, tone }. With `href` the title's link covers the card. */
export function card({ title, line, foot, href, pills = [] }) {
  const tags = pills.length
    ? `<div class="pb-card__pills">${pills.map((p) => (typeof p === 'string' ? pill(p) : pill(p.text, p.tone))).join('')}</div>`
    : '';
  const name = href ? `<a href="${url(href)}"${external(href)}>${esc(title)}</a>` : esc(title);
  return `<li class="pb-card">${tags}<h3 class="pb-card__title">${name}</h3>${line ? `<p class="pb-card__line">${esc(line)}</p>` : ''}${foot ? `<p class="pb-card__foot">${esc(foot)}</p>` : ''}</li>`;
}

/** A grid of cards, from the strings that card() returns. An empty list gives no grid. */
export const cardGrid = (cards) => (cards.length ? `<ul class="pb-cards">${cards.join('')}</ul>` : '');

/** The foot: one line of text and the public sites. */
export function footer({ sites, built, current }) {
  known(sites, current);
  return `<footer class="pb-footer"><div class="pb-wrap pb-footer__in"><p>${esc(built)}</p>${siteNav(sites, current, 'pb-footer__nav')}</div></footer>`;
}

/**
 * A whole page. `modules` names the CSS to inline after tokens and base, always in the order of
 * MODULES. `icons` is the HTML of favicon/links.nix, `head` more HTML for the head, `body` the HTML
 * of the body. The page loads no script.
 */
export function page({ lang = 'en', title, description, modules = [], head = '', icons = '', body }) {
  if (!title || !description) throw new Error('design kit: a page needs a title and a description');
  for (const m of modules) if (!MODULES.includes(m)) throw new Error(`design kit: no module "${m}"`);
  const styles = ['tokens', 'base', ...MODULES.filter((m) => modules.includes(m))].map(css).join('');
  return `<!doctype html>\n<html lang="${esc(lang)}"><head><meta charset="utf-8"><meta content="width=device-width, initial-scale=1" name="viewport"><title>${esc(title)}</title><meta content="${esc(description)}" name="description"><meta content="#0B0D12" media="(prefers-color-scheme: dark)" name="theme-color"><meta content="#FFFFFF" media="(prefers-color-scheme: light)" name="theme-color">${icons}${FONTS}<style>\n${styles}</style>${head}</head>\n<body>${body}</body></html>\n`;
}
