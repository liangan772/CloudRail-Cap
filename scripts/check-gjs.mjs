/**
 * Validates every `.gjs` file in the plugin with `content-tag`, the same
 * preprocessor Discourse's asset build uses. This is the authoritative check:
 * it reproduces the build's error messages verbatim, e.g.
 *
 *   Parse Error at discourse/plugins/Foo/.../cap-checkbox.gjs:48:11: 48:11
 *
 * Why this exists
 * ---------------
 * A `.gjs` file is a single ES module. The `<template>` tag must either be the
 * operand of `export default`, or a member inside `export default class { ... }`.
 * The older shape that circulated widely - a `<template>` block followed by a
 * separate `<script>...</script>` block - is NOT valid gjs. It fails at bundle
 * time and takes the *entire plugin* down with it: no connectors, no initializer,
 * no widget, and no runtime error to explain why. The only clue is an
 * `app.js` line reporting a plugin compile error.
 *
 * A previous version of this script stripped `<template>` and `<script>` tags
 * before parsing the remainder as JavaScript. Every file passed, because the
 * thing that was wrong was exactly the part being removed. Hence this rewrite:
 * parse the file as-is, with the real parser, and let it fail.
 *
 * Usage
 * -----
 *   node scripts/check-gjs.mjs [rootDir]
 *
 * Requires `content-tag` (a dev dependency; see scripts/README.md).
 * Exit code 0 = all files valid, 1 = at least one problem, 2 = setup problem.
 */

import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

let Preprocessor;
try {
  ({ Preprocessor } = require("content-tag"));
} catch {
  console.error(
    "Missing dependency: content-tag\n\n" +
      "Install it once with:\n" +
      "  npm install --no-save content-tag\n\n" +
      "or point NODE_PATH at a directory that already has it."
  );
  process.exit(2);
}

const processor = new Preprocessor();

/** Collects every `.gjs` file under `dir`, skipping build output. */
function findGjsFiles(dir) {
  const out = [];
  const skip = new Set(["node_modules", ".git", "tmp", "dist", "vendor"]);

  const walk = (current) => {
    let entries;
    try {
      entries = readdirSync(current, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      if (entry.isDirectory()) {
        if (!skip.has(entry.name)) {
          walk(join(current, entry.name));
        }
      } else if (entry.name.endsWith(".gjs")) {
        out.push(join(current, entry.name));
      }
    }
  };

  walk(dir);
  return out.sort();
}

const root = process.argv[2] || ".";
const files = findGjsFiles(root);

if (files.length === 0) {
  console.error(`No .gjs files found under ${root}`);
  process.exit(1);
}

let failures = 0;

for (const file of files) {
  const source = readFileSync(file, "utf8");
  const shown = relative(root, file) || file;

  try {
    processor.process(source, { filename: shown });
    console.log(`OK    ${shown}`);
  } catch (error) {
    failures += 1;
    console.log(`FAIL  ${shown}`);

    const message = error.message.split("\n")[0];
    console.log(`        ${message}`);

    // Point at the actual offending line, since the parser reports 1-based
    // line and column but the message alone is easy to misread.
    const match = /:(\d+):(\d+)/.exec(message);
    if (match) {
      const line = Number(match[1]);
      const column = Number(match[2]);
      const text = source.split("\n")[line - 1];

      if (text !== undefined) {
        console.log(`        line ${line}: ${text.trim()}`);
      }

      if (/<\/?script/i.test(text || "")) {
        console.log(
          "        ^ a <script> tag is not valid in .gjs. Move the imports " +
            "and class to the top level and put <template> inside the class body."
        );
      }
    }
  }
}

console.log("");

if (failures === 0) {
  console.log(`All ${files.length} .gjs file(s) valid.`);
  process.exit(0);
}

console.log(`${failures} of ${files.length} .gjs file(s) invalid.`);
process.exit(1);
