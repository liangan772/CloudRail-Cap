/**
 * Renders all three theme modes with the plugin's real compiled CSS, on both a
 * light and a dark simulated forum, and reports the widget's actual computed
 * background. Proves that:
 *   - auto  follows the forum (the SCSS uses Discourse's own variables)
 *   - light is pinned light
 *   - dark  is pinned dark
 *
 * The CSS is injected verbatim from the compiled stylesheet so this tests the
 * real selectors, not a hand-written approximation.
 *
 * Usage:
 *   CAP_INSTANCE_URL=https://cap.example.com CAP_SITE_KEY=abc123 \
 *   node scripts/browser/widget-theme.mjs
 *
 * Requires playwright and sass. Resolution order: PLAYWRIGHT_PATH / SASS_PATH,
 * then the package name itself.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, "..", "..");

function loadModule(envVar, names, label) {
  const candidates = [];
  if (process.env[envVar]) candidates.push(process.env[envVar]);
  candidates.push(...names);

  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch {
      // try the next candidate
    }
  }

  console.error(`Could not load ${label}. Install it or set ${envVar}.`);
  process.exit(3);
}

const { chromium } = loadModule("PLAYWRIGHT_PATH", ["playwright", "playwright-core"], "playwright");
const sass = loadModule("SASS_PATH", ["sass"], "sass");

const SCSS = fs.readFileSync(
  path.join(REPO, "assets", "stylesheets", "cap-verification.scss"),
  "utf8",
);

const SCRIPT =
  process.env.CAP_WIDGET_SCRIPT || "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.58";
const INSTANCE = (process.env.CAP_INSTANCE_URL || "https://jq.crbbsx.com").replace(/\/$/, "");
const SITE_KEY = process.env.CAP_SITE_KEY || "c87f54f192";
const ENDPOINT = `${INSTANCE}/${SITE_KEY}/`;

// Discourse's variables resolve differently per scheme. Feed the two schemes
// the same values Discourse ships, so `auto` has something real to resolve.
const LIGHT_VARS = `
  --secondary: #ffffff; --primary: #222222; --primary-low: #e9e9e9;
  --primary-medium: #919191; --primary-very-low: #f8f8f8;
  --tertiary: #0088cc; --success: #009900; --danger: #cc0000;
  --danger-low: #ffeeee; --d-border-radius: 8px; --font-down-1: 0.87em;
`;
const DARK_VARS = `
  --secondary: #1f1f1f; --primary: #e8e8e8; --primary-low: #3a3a3a;
  --primary-medium: #8a8a8a; --primary-very-low: #2b2b2b;
  --tertiary: #4aa3df; --success: #4caf50; --danger: #e05252;
  --danger-low: #3a2020; --d-border-radius: 8px; --font-down-1: 0.87em;
`;

const widgetCSS = sass.compileString(SCSS).css.toString();

function page(schemeVars, mode) {
  return `<!doctype html>
<html><head><meta charset="utf-8"><style>
  body { margin: 0; padding: 30px; ${schemeVars}
         background: var(--secondary); color: var(--primary); }
  ${widgetCSS}
</style></head>
<body>
  <div class="cap-verification-widget cap-verification-widget--${mode}">
    <cap-widget data-cap-api-endpoint="${ENDPOINT}"></cap-widget>
  </div>
  <script type="module" src="${SCRIPT}"></script>
</body></html>`;
}

const browser = await chromium.launch();
const results = [];

for (const [schemeName, schemeVars] of [["light forum", LIGHT_VARS], ["dark forum", DARK_VARS]]) {
  for (const mode of ["auto", "light", "dark"]) {
    const p = await browser.newPage();
    await p.setContent(page(schemeVars, mode), { waitUntil: "load" });
    await p.waitForFunction(() => !!customElements.get("cap-widget"), { timeout: 30000 }).catch(() => {});
    await p.waitForTimeout(1200);

    const r = await p.evaluate(() => {
      const el = document.querySelector("cap-widget");
      const inner = el?.shadowRoot?.querySelector(".captcha");
      if (!inner) return { error: "no .captcha" };
      const cs = getComputedStyle(inner);
      return { bg: cs.backgroundColor, fg: cs.color };
    });
    await p.close();
    results.push({ scheme: schemeName, mode, ...r });
  }
}

await browser.close();

console.log("scheme      mode    widget bg            widget text");
console.log("-".repeat(60));
for (const r of results) {
  console.log(
    r.scheme.padEnd(12) + r.mode.padEnd(8) + String(r.bg).padEnd(21) + String(r.fg),
  );
}

function lum(rgb) {
  const m = (rgb || "").match(/(\d+),\s*(\d+),\s*(\d+)/);
  if (!m) return null;
  return (Number(m[1]) + Number(m[2]) + Number(m[3])) / 3;
}

console.log("");
const by = {};
for (const r of results) by[`${r.scheme}/${r.mode}`] = lum(r.bg);

console.log("checks:");
const c1 = by["light forum/auto"] > 200;
const c2 = by["dark forum/auto"] < 80;
const c3 = by["light forum/light"] > 200;
const c4 = by["dark forum/light"] > 200;
const c5 = by["light forum/dark"] < 80;
const c6 = by["dark forum/dark"] < 80;

console.log("  auto  follows a light forum  ->", c1 ? "OK" : "FAIL");
console.log("  auto  follows a dark  forum  ->", c2 ? "OK" : "FAIL");
console.log("  light pinned on light forum  ->", c3 ? "OK" : "FAIL");
console.log("  light pinned on dark  forum  ->", c4 ? "OK" : "FAIL");
console.log("  dark  pinned on light forum  ->", c5 ? "OK" : "FAIL");
console.log("  dark  pinned on dark  forum  ->", c6 ? "OK" : "FAIL");

const allOk = c1 && c2 && c3 && c4 && c5 && c6;
console.log("\nVERDICT: " + (allOk ? "all three modes behave as documented" : "SOME MODES ARE WRONG"));
process.exit(allOk ? 0 : 1);
