// The few things the content generator needs from Node: files, a directory listing, the JSON of
// .zenodo.json and one git command. Paths are relative to site/content, where `gleam run` runs.
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { toList } from "./gleam.mjs";

// The file's text, or "" when it does not exist.
export function read(path) {
  return existsSync(path) ? readFileSync(path, "utf8") : "";
}

export function write(path, text) {
  writeFileSync(path, text);
}

// The names in a directory, sorted; [] when it does not exist.
export function list(dir) {
  return toList(existsSync(dir) ? readdirSync(dir).sort() : []);
}

// The people of .zenodo.json, one per line: role, name, orcid, affiliation, type, tab-separated.
export function zenodo_people(path) {
  if (!existsSync(path)) return "";
  const meta = JSON.parse(readFileSync(path, "utf8"));
  const row = (role, p) =>
    [role, p.name || "", p.orcid || "", p.affiliation || "", p.type || ""].join("\t");
  return [
    ...(meta.creators || []).map((p) => row("creator", p)),
    ...(meta.contributors || []).map((p) => row("contributor", p)),
  ].join("\n");
}

// The preprints that document the work in .zenodo.json (relation isDocumentedBy, resource type
// publication-preprint), one identifier per line.
export function zenodo_preprints(path) {
  if (!existsSync(path)) return "";
  const meta = JSON.parse(readFileSync(path, "utf8"));
  return (meta.related_identifiers || [])
    .filter((r) => r.relation === "isDocumentedBy" && r.resource_type === "publication-preprint")
    .map((r) => r.identifier)
    .join("\n");
}

// The keys a source file of the page asks for: the literal of each `t(l, "...")`,
// unescaped. Comment lines are skipped, so a doc comment that shows the call is not a sentence.
export function sentences(code) {
  const live = code.replace(/^\s*\/\/.*$/gm, "");
  return toList(
    [...live.matchAll(/\bt\(\s*l,\s*"((?:[^"\\]|\\.)*)"/g)].map((m) =>
      m[1].replace(/\\(.)/g, "$1"),
    ),
  );
}

// Stop the generator with an exit code, so that `just site` and CI fail.
export function exit(code) {
  process.exit(code);
}

// The short hash of the commit that is built: WW3_GPU_REV when the Nix build sets it (its source
// has no .git), else Git's, else "unversioned".
export function revision() {
  if (process.env.WW3_GPU_REV) return process.env.WW3_GPU_REV;
  try {
    return execSync("git rev-parse --short HEAD", { stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
  } catch (_) {
    return "unversioned";
  }
}

// How many commits the built commit has: WW3_GPU_COMMITS when the Nix build sets it (the pin's
// count, written by scripts/ww3-pin.sh), else Git's, else "".
export function commits() {
  if (process.env.WW3_GPU_COMMITS) return process.env.WW3_GPU_COMMITS;
  try {
    return execSync("git rev-list --count HEAD", { stdio: ["ignore", "pipe", "ignore"] })
      .toString()
      .trim();
  } catch (_) {
    return "";
  }
}

// The size a PNG was drawn at, "width height" in CSS pixels: half its pixels, since the drawings
// are taken at twice their size (ww3-gpu's scripts/archify_shot.py). "" when it is not a PNG.
export function png_size(path) {
  if (!existsSync(path)) return "";
  const head = readFileSync(path).subarray(0, 24);
  if (head.length < 24 || head.toString("latin1", 12, 16) !== "IHDR") return "";
  return `${Math.round(head.readUInt32BE(16) / 2)} ${Math.round(head.readUInt32BE(20) / 2)}`;
}

// A locale file, site/locales/<lang>.json: its pairs of key and sentence, in the file's order.
// [] when the file does not exist; a value that is not a string stops the build.
export function locale(path) {
  if (!existsSync(path)) return toList([]);
  const pairs = Object.entries(JSON.parse(readFileSync(path, "utf8")));
  for (const [key, value] of pairs) {
    if (typeof value !== "string") throw new Error(`${path}: ${key} is not a string`);
  }
  return toList(pairs);
}
