// node --test design/test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { card, cardGrid, chrome, css, eye, footer, hero, main, MODULES, page, pill, section } from './kit.mjs';
import { barStyle, injectHtml, MARKER } from './inject.mjs';

const sites = [
  { id: 'www', label: 'www', url: 'https://www.piabrota.art/', access: 'public' },
  { id: 'proof', label: 'proof', url: 'https://proof.piabrota.art/', access: 'public' },
  { id: 'rig', label: 'rig', url: 'https://rig.piabrota.art/', access: 'login' },
];
const evil = '<script>alert("x")</script> & \'q\'';
const safe = (html) => assert.ok(!html.includes('<script>') && !html.includes('alert("x")'), html);

test('every text is escaped', () => {
  safe(hero({ eyebrow: evil, title: evil, tail: evil, lede: evil, stats: [{ value: evil, label: evil }], actions: [{ label: evil, href: '/x' }] }));
  safe(section({ id: evil, title: evil, count: evil, note: evil, body: '' }));
  safe(card({ title: evil, line: evil, foot: evil, href: '/x', pills: [evil, { text: evil, tone: evil }] }));
  safe(footer({ sites, built: evil }));
  safe(page({ title: evil, description: evil, body: '' }));
  assert.match(card({ title: 'a"b', href: '/x"y' }), /href="\/x&quot;y"/);
});

test('a link with a script scheme is refused', () => {
  assert.throws(() => card({ title: 't', href: 'javascript:alert(1)' }), /scheme/);
  assert.throws(() => hero({ title: 't', actions: [{ label: 'l', href: ' data:text/html,x' }] }), /scheme/);
  assert.doesNotThrow(() => card({ title: 't', href: 'https://example.org/a?b=c&d=e' }));
});

test('hero: eyebrow, title with a muted tail, lede, stats as a dl, one primary action', () => {
  const html = hero({ eyebrow: 'e', title: 't', tail: '· tail', lede: 'l', stats: [{ value: 3, label: 'pages' }], actions: [{ label: 'go', href: '/a', variant: 'primary' }, { label: 'abc1234', href: '/b', variant: 'mono' }, { label: 'plain', href: 'https://x.org/' }] });
  assert.match(html, /<p class="pb-eyebrow">e<\/p>/);
  assert.match(html, /<h1 class="pb-title">t <span class="pb-tail">· tail<\/span><\/h1>/);
  assert.match(html, /<dl class="pb-stats"><div><dt>pages<\/dt><dd>3<\/dd><\/div><\/dl>/);
  assert.equal(html.match(/pb-btn--primary/g).length, 1);
  assert.match(html, /pb-btn--mono/);
  assert.match(html, /rel="noopener"/);
  assert.doesNotMatch(hero({ title: 't' }), /pb-stats|pb-actions|pb-lede|pb-eyebrow|pb-hero__mark/);
});

test('section: heading, count and body; no typed number', () => {
  const html = section({ id: 'a', title: 'T', count: 4, note: 'n', body: '<p>b</p>' });
  assert.match(html, /<section class="pb-section" id="a">/);
  assert.match(html, /<h2 class="pb-section__title">T<\/h2><span class="pb-count">4<\/span>/);
  assert.match(html, /<p>b<\/p>/);
  assert.doesNotMatch(html, /§/);
  assert.match(main(html), /^<main class="pb-main"/);
});

test('cards: a card has pills, a title, a line, a foot; a link covers it; an empty grid is nothing', () => {
  const html = card({ title: 'T', line: 'L', foot: '/f', href: '/p', pills: ['EN', { text: 'live', tone: 'ok' }] });
  assert.match(html, /^<li class="pb-card"><div class="pb-card__pills"><span class="pb-pill">EN<\/span><span class="pb-pill pb-pill--ok">live<\/span><\/div><h3 class="pb-card__title"><a href="\/p">T<\/a><\/h3><p class="pb-card__line">L<\/p><p class="pb-card__foot">\/f<\/p><\/li>$/);
  assert.doesNotMatch(card({ title: 'T' }), /<a |pb-card__pills|pb-card__line|pb-card__foot/);
  assert.equal(cardGrid([]), '');
  assert.equal(cardGrid(['<li>a</li>', '<li>b</li>']), '<ul class="pb-cards"><li>a</li><li>b</li></ul>');
});

test('pill: a tone that is not known cannot reach the class', () => {
  assert.equal(pill('x', 'ok'), '<span class="pb-pill pb-pill--ok">x</span>');
  assert.equal(pill('x', '"><script>'), '<span class="pb-pill">x</span>');
});

test('chrome: the page header lists the public sites and marks the current one', () => {
  const html = chrome({ current: 'proof', sites });
  assert.match(html, /aria-current="page">proof<\/a>/);
  assert.match(html, /href="https:\/\/www.piabrota.art\/">www<\/a>/);
  assert.doesNotMatch(html, /rig|data-pb-chrome/);
  assert.throws(() => chrome({ current: 'nope', sites }), /not in design\/sites.nix/);
});

test('chrome: the bar carries the marker, the eye and a link back to the index', () => {
  const html = chrome({ current: 'proof', sites, index: '/', bar: true });
  assert.ok(html.includes(MARKER));
  assert.match(html, /<a class="pb-back" href="\/">\u2190 proof index<\/a>/);
  assert.match(html, /<svg [^>]*class="pb-eye"/);
  assert.doesNotMatch(chrome({ current: 'proof', sites, bar: true }), /pb-back/);
});

test('the eye has one copy', () => {
  assert.equal(eye(28).match(/#BC2318/g).length, 1);
  assert.match(eye(22), /width="22"/);
});

test('footer: the public sites and the line', () => {
  const html = footer({ sites, current: 'proof', built: 'Built.' });
  assert.match(html, /<p>Built\.<\/p>/);
  assert.match(html, /aria-current="page">proof/);
  assert.doesNotMatch(html, /rig/);
});

test('page: inlines tokens, base and exactly the modules asked, in a fixed order', () => {
  const html = page({ title: 'T', description: 'D', modules: ['footer', 'cards'], icons: '<link rel="icon" href="/i.svg">', body: '<p>b</p>' });
  assert.ok(html.includes(css('tokens')) && html.includes(css('base')));
  assert.ok(html.includes(css('cards')) && html.includes(css('footer')));
  for (const m of MODULES.filter((m) => !['cards', 'footer'].includes(m))) assert.ok(!html.includes(css(m)), `${m} was not asked`);
  assert.ok(html.indexOf(css('tokens')) < html.indexOf(css('base')) && html.indexOf(css('base')) < html.indexOf(css('cards')) && html.indexOf(css('cards')) < html.indexOf(css('footer')));
  assert.match(html, /<html lang="en">/);
  assert.match(html, /<title>T<\/title><meta content="D" name="description">/);
  assert.ok(html.includes('<link rel="icon" href="/i.svg">'));
  assert.doesNotMatch(html, /<script/);
  assert.throws(() => page({ title: 'T', description: 'D', modules: ['nope'], body: '' }), /no module/);
  assert.throws(() => page({ title: 'T', body: '' }), /description/);
});

test('modules: every class is prefixed, and one needs no other but tokens and base', () => {
  for (const m of MODULES) {
    const classes = [...css(m).replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/\.([a-z][\w-]*)/g)].map((x) => x[1]);
    assert.ok(classes.length > 0 && classes.every((c) => c.startsWith('pb-')), `${m}: ${classes.filter((c) => !c.startsWith('pb-'))}`);
    for (const other of MODULES.filter((o) => o !== m)) {
      assert.ok(!css(m).replace(/\/\*[\s\S]*?\*\//g, '').includes(`.pb-${other}`), `${m} depends on ${other}`);
    }
  }
});

const foreign = (body = '<main>x</main>') => `<!doctype html><html><head><title>t</title><script>var s = "<body class=fake>";</script></head>\n<body class="a">${body}</body></html>`;

test('inject: the bar goes right after the real <body> tag, once', () => {
  const once = injectHtml(foreign(), { current: 'proof', sites, index: '/' });
  assert.ok(once.includes('</head>\n<body class="a"><style>'));
  assert.equal(once.split(MARKER).length - 1, 1);
  assert.equal(injectHtml(once, { current: 'proof', sites, index: '/' }), once);
  assert.ok(once.includes('<script>var s = "<body class=fake>";</script>'), 'the page is otherwise the same');
  assert.ok(once.endsWith('<main>x</main></body></html>'));
});

test('inject: marks the current site; fails with a message when there is no <body>', () => {
  const html = injectHtml(foreign(), { current: 'proof', sites, index: '/' });
  assert.match(html, /href="https:\/\/proof.piabrota.art\/" aria-current="page">proof/);
  assert.match(html, /\u2190 proof index/);
  assert.throws(() => injectHtml('<html><head></head><p>x</p></html>', { current: 'proof', sites }, 'x/y.html'), /x\/y.html: no <body> tag/);
});

test('inject: the bar\'s CSS is scoped to .pb-chrome, dark in any theme, and the archify rule only on archify pages', () => {
  for (const html of ['', 'archify-theme']) {
    const selectors = [...barStyle(html).replace(/@media[^{]*\{/g, '').matchAll(/(?:^|\})\s*([^{}@]+)\{/g)].map((m) => m[1].trim());
    assert.ok(selectors.length > 10);
    for (const s of selectors) for (const part of s.split(',')) assert.ok(part.includes('.pb-chrome'), `selector outside the bar: ${part}`);
  }
  assert.match(barStyle(), /^\.pb-chrome--bar\{--bg: #0B0D12;/);
  assert.doesNotMatch(barStyle(), /--bg: #FFFFFF|\.toolbar/);
  assert.match(barStyle('archify-theme'), /\.pb-chrome--bar ~ \.toolbar/);
});

// The values of one :root block (and of the light one) as { name: value }.
function tokensOf(text) {
  const [dark, light = ''] = text.split(/@media \(prefers-color-scheme: light\)/);
  const read = (block) => Object.fromEntries([...block.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
  return { dark: read(/:root\s*\{[^}]*\}/.exec(dark)[0]), light: read(/:root\s*\{[^}]*\}/.exec(light)?.[0] ?? '') };
}

test('drift: the tokens of the kit are those of site/static/style.css', () => {
  const kit = tokensOf(readFileSync(new URL('./css/tokens.css', import.meta.url), 'utf8'));
  const home = tokensOf(readFileSync(new URL('../site/static/style.css', import.meta.url), 'utf8'));
  for (const mode of ['dark', 'light']) {
    for (const [name, value] of Object.entries(home[mode])) {
      if (name in kit[mode]) assert.equal(kit[mode][name], value, `${mode} ${name}`);
    }
  }
  for (const name of ['--bg', '--surface', '--border', '--text', '--muted', '--accent', '--accent-text', '--ok', '--warn', '--none']) {
    assert.ok(name in kit.dark && name in home.dark, `${name} is in both`);
  }
  // The names that a mode does not set keep the dark value in both files, so they must agree there.
  for (const name of Object.keys(kit.dark)) if (name in home.dark) assert.equal(kit.dark[name], home.dark[name], name);
});

test('drift: the theme switch of site/static/style.css flips to the same tokens', () => {
  const text = readFileSync(new URL('../site/static/style.css', import.meta.url), 'utf8');
  const { dark, light } = tokensOf(text);
  const read = (block) => Object.fromEntries([...block.matchAll(/(--[\w-]+):\s*([^;]+);/g)].map((m) => [m[1], m[2].trim()]));
  const flipped = (scheme) => read(new RegExp(`@media \\(prefers-color-scheme: ${scheme}\\) \\{\\s*:root:has\\(#theme:checked\\) \\{[^}]*\\}`).exec(text)[0]);
  const toLight = flipped('dark');
  const toDark = flipped('light');
  assert.deepEqual(toLight, light, 'checked on a dark system: the light tokens');
  for (const name of Object.keys(light)) assert.equal(toDark[name], dark[name], `checked on a light system: dark ${name}`);
});

test('drift: the tokens of the kit are the table of site/DESIGN.md', () => {
  const kit = tokensOf(readFileSync(new URL('./css/tokens.css', import.meta.url), 'utf8'));
  const table = readFileSync(new URL('../site/DESIGN.md', import.meta.url), 'utf8');
  let rows = 0;
  for (const line of table.split('\n')) {
    const cells = line.split('|').map((c) => c.trim());
    const names = cells[1]?.match(/--[\w-]+/g);
    const dark = cells[2]?.match(/#[0-9A-Fa-f]{6}/g);
    const light = cells[3]?.match(/#[0-9A-Fa-f]{6}/g);
    if (!names || !dark || !light) continue;
    rows += 1;
    names.forEach((name, i) => {
      assert.equal(kit.dark[name], dark[i], `dark ${name}`);
      assert.equal(kit.light[name] ?? kit.dark[name], light[i], `light ${name}`);
    });
  }
  assert.equal(rows, 6, 'the table rows with colours: bg, surface, border, text and muted, accent, accent-text');
});

test('sites.nix: the public sites have ids, addresses and a line', (t) => {
  let list;
  try {
    list = JSON.parse(execFileSync('nix-instantiate', ['--eval', '--json', '--strict', '-E', `(import ${new URL('./sites.nix', import.meta.url).pathname}).sites`], { encoding: 'utf8' }));
  } catch {
    t.skip('nix-instantiate is not on the path');
    return;
  }
  assert.deepEqual(new Set(list.map((s) => s.id)).size, list.length, 'ids are unique');
  for (const s of list) {
    assert.deepEqual(Object.keys(s).sort(), ['access', 'host', 'id', 'label', 'line', 'url']);
    assert.ok(['public', 'login'].includes(s.access));
    assert.ok(new URL(s.url).host === s.host, `${s.id}: url and host agree`);
  }
  assert.deepEqual(list.filter((s) => s.access === 'login').map((s) => s.id).sort(), ['hermes', 'rig']);
});
