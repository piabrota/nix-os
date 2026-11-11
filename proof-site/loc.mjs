// Lines of code of the proofs of h0ffmann/proof, as JSON: what index.mjs shows in the hero. The build
// runs it on the pinned source, so the numbers are those of the commit the pages come from.
//
// A line of code is a line that is not blank and not only a comment, the rule of the repository's own
// badge (its scripts/loc.py), with its scan: a comment after code on a line is not read, so a block
// comment that opens there is not seen. vendor/ is other people's code and is left out. "Z3" is the
// Scala of z3-scala/, where every Z3 check of the repository is written.
//
//   node loc.mjs <source> > loc.json
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// id: what a file must be, its line comment and its block comment.
export const LANGUAGES = {
  lean: { label: 'Lean 4', match: (p) => p.endsWith('.lean'), line: '--', block: ['/-', '-/'] },
  agda: { label: 'Agda', match: (p) => p.endsWith('.agda'), line: '--', block: ['{-', '-}'] },
  z3: { label: 'Z3', match: (p) => p.startsWith('z3-scala/') && p.endsWith('.scala'), line: '//', block: ['/*', '*/'] },
};

/** Lines that are not blank and not only a comment. */
export function countCode(text, { line, block: [open, close] }) {
  let n = 0;
  let inBlock = false;
  // Python's str.splitlines, so the counts are the badge's to the line.
  for (const raw of text.split(/\r\n|[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]/)) {
    let s = raw.trim();
    let code = false;
    while (s) {
      if (inBlock) {
        const i = s.indexOf(close);
        if (i < 0) break;
        s = s.slice(i + close.length).trim();
        inBlock = false;
      } else if (s.startsWith(open)) {
        s = s.slice(open.length);
        inBlock = true;
      } else if (s.startsWith(line)) {
        break;
      } else {
        code = true; // code first; what follows on the line is not read
        break;
      }
    }
    if (code) n += 1;
  }
  return n;
}

function* files(dir, root = dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, e.name);
    const rel = relative(root, full).split(sep).join('/');
    if (e.isDirectory()) {
      if (rel !== 'vendor' && e.name !== '.git') yield* files(full, root);
    } else if (e.isFile()) yield rel;
  }
}

/** { lean: { label, files, lines }, ... } for the source tree at `root`. */
export function count(root) {
  const out = Object.fromEntries(Object.entries(LANGUAGES).map(([id, l]) => [id, { label: l.label, files: 0, lines: 0 }]));
  for (const rel of files(root)) {
    for (const [id, l] of Object.entries(LANGUAGES)) {
      if (!l.match(rel)) continue;
      out[id].files += 1;
      out[id].lines += countCode(readFileSync(join(root, rel), 'utf8'), l);
    }
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [root] = process.argv.slice(2);
  if (!root) throw new Error('usage: loc.mjs <source> > loc.json');
  const c = count(root);
  for (const [id, v] of Object.entries(c)) if (v.files === 0) throw new Error(`loc.mjs: no ${LANGUAGES[id].label} file under ${root}`);
  process.stdout.write(JSON.stringify(c));
}
