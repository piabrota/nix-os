// node --test proof-site/test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { decode, groupOf, groupTitle, langOf, scan, titleOf } from './manifest.mjs';
import { cleanTitle, pirsigIndex, proofIndex } from './index.mjs';

const sites = [{ id: 'proof', label: 'proof', url: 'https://proof.piabrota.art/', access: 'public' }, { id: 'pirsig', label: 'pirsig', url: 'https://pirsig.piabrota.art/', access: 'public' }];
const ctx = { rev: 'b863c15e56a22afaab2fa228fe5eb85847c1d6c4', sites, icons: '' };

test('titles: entities decoded, white space folded, empty when missing', () => {
  assert.equal(titleOf('<title>z3-scala: every\nZ3 &amp; more &#39;x&#39; &#x41;</title>'), "z3-scala: every Z3 & more 'x' A");
  assert.equal(titleOf('<p>no title</p>'), '');
  assert.equal(decode('&unknown; &lt;b&gt;'), '&unknown; <b>');
  assert.equal(langOf('<html lang="pt-BR">'), 'pt-BR');
  assert.equal(langOf('<html>'), 'en');
});

test('groups: the first folder under proof/, docs/<name> for docs, a pirsig folder as it is', () => {
  assert.equal(groupOf('proof', 'proof/contextual-bandits/script/results.html'), 'contextual-bandits');
  assert.equal(groupOf('proof', 'proof/docs/decisions/0001.html'), 'docs/decisions');
  assert.equal(groupOf('proof', 'proof/index.html'), '');
  assert.equal(groupOf('pirsig', 'figures/para.html'), 'figures');
  assert.equal(groupTitle('z3-scala', 'z3-scala: every Z3 check of this repository, in Scala · proof'), 'z3-scala');
  assert.equal(groupTitle('docs/decisions', ''), 'Decisions');
});

function tree() {
  const dir = mkdtempSync(join(tmpdir(), 'proof-site-'));
  const put = (path, html) => {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), html);
  };
  put('proof/index.html', '<html lang="en"><title>proof</title>');
  put('proof/a/index.html', '<html lang="en"><title>Alpha: the first · proof</title>');
  put('proof/a/index.pt-BR.html', '<html lang="pt-BR"><title>Alfa · proof</title>');
  put('proof/docs/diagrams/index.html', '<html lang="en"><title>Diagrams · proof</title>');
  put('proof/docs/diagrams/en/x.html', '<html lang="en"><title>One round: how it goes Diagram</title>archify-theme');
  put('proof/docs/diagrams/pt-BR/x.html', '<html lang="pt-BR"><title>Diagrama Uma rodada</title>archify-theme');
  put('videos/index.html', '<html lang="pt-BR"><title>Vídeos</title><p>2 vídeos indexados.</p>');
  return dir;
}

test('scan: group, language, kind, the dark address of archify pages, the video count', () => {
  const dir = tree();
  const m = scan(dir, 'proof');
  const by = Object.fromEntries(m.pages.map((p) => [p.path, p]));
  assert.equal(by['proof/docs/diagrams/en/x.html'].href, 'proof/docs/diagrams/en/x.html?theme=dark');
  assert.equal(by['proof/docs/diagrams/en/x.html'].kind, 'diagram');
  assert.equal(by['proof/a/index.pt-BR.html'].lang, 'pt-BR');
  assert.equal(by['proof/a/index.html'].href, 'proof/a/index.html');
  assert.deepEqual(m.groups, { a: 'Alpha', 'docs/diagrams': 'Diagrams' });
  assert.equal(m.videos, 2);
  assert.equal(scan(dir, 'proof').pages.some((p) => p.path === 'index.html'), false);
});

test('proof index: a section for each group, then the diagrams by language; the repository index is an action, not a card', () => {
  const html = proofIndex(scan(tree(), 'proof'), ctx);
  assert.match(html, /<h2 class="pb-section__title">Alpha<\/h2><span class="pb-count">2<\/span>/);
  assert.match(html, /<h2 class="pb-section__title">Diagrams<\/h2><span class="pb-count">2<\/span>/);
  assert.ok(html.indexOf('>Alpha<') < html.indexOf('>Diagrams<'));
  assert.match(html, /<h3 class="pb-sub">English<\/h3>/);
  assert.match(html, /<h3 class="pb-sub">Português \(BR\)<\/h3>/);
  assert.match(html, /href="proof\/docs\/diagrams\/en\/x.html\?theme=dark"/);
  assert.match(html, /<a class="pb-btn" href="proof\/index.html">Its own index<\/a>/);
  assert.doesNotMatch(html, /pb-card__title"><a href="proof\/index.html"/);
  assert.match(html, /<dt>pages<\/dt><dd>2<\/dd>/);
  assert.match(html, /<dt>languages<\/dt><dd>2<\/dd>/);
  assert.match(html, />b863c15<\/a>/);
  assert.doesNotMatch(html, /<script/);
});

test('proof index: the cards of a group show a language pill only when the group has two languages', () => {
  const html = proofIndex(scan(tree(), 'proof'), ctx);
  const alpha = html.slice(html.indexOf('id="a"'), html.indexOf('id="docs-decisions"') > 0 ? html.indexOf('id="docs-decisions"') : html.indexOf('id="diagrams"'));
  assert.equal(alpha.match(/pb-pill/g).length, 2);
});

test('diagram titles: the card splits "Name: what it says" and drops the Diagram word', () => {
  const html = proofIndex(scan(tree(), 'proof'), ctx);
  assert.match(html, /<h3 class="pb-card__title"><a href="proof\/docs\/diagrams\/en\/x.html\?theme=dark">One round<\/a><\/h3><p class="pb-card__line">how it goes<\/p>/);
  assert.equal(cleanTitle({ kind: 'diagram', title: 'Diagrama Uma rodada' }), 'Uma rodada');
  assert.equal(cleanTitle({ kind: 'page', title: 'Diagrama Uma rodada · proof' }), 'Diagrama Uma rodada');
});

test('pirsig index: the video count is said only when the page said it', () => {
  const m = scan(tree(), 'pirsig');
  const withCount = pirsigIndex(m, { ...ctx, rev: 'caa7bc7722f875bf617f59d0eaa6fffe9f201c27' });
  assert.match(withCount, /2 vídeos indexados/);
  assert.match(withCount, /<dt>video notes<\/dt><dd>2<\/dd>/);
  const without = pirsigIndex({ ...m, videos: null }, ctx);
  assert.doesNotMatch(without, /indexado|<dt>video note/);
});
