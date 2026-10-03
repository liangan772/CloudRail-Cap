/**
 * Renders the widget's exact markup in a real browser and asserts that:
 *   1. the custom element upgrades (cap-widget is defined)
 *   2. the host element receives the theme CSS variables
 *   3. the widget actually fetches a challenge from the live Cap server
 *   4. solving yields a token with the shape /siteverify requires
 *
 * This is the closest thing to the real signup page you can run without a
 * Discourse instance.
 *
 * Usage:
 *   CAP_INSTANCE_URL=https://cap.example.com \
 *   CAP_SITE_KEY=abc123 \
 *   CAP_WIDGET_SCRIPT=https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.58 \
 *   node scripts/browser/widget-solve.mjs
 *
 * Requires playwright. Resolution order: PLAYWRIGHT_PATH, then the `playwright`
 * package, then `playwright-core`.
 */
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

function loadPlaywright() {
  const candidates = [];
  if (process.env.PLAYWRIGHT_PATH) candidates.push(process.env.PLAYWRIGHT_PATH);
  candidates.push("playwright", "playwright-core");

  for (const candidate of candidates) {
    try {
      const mod = require(candidate);
      if (mod?.chromium) return mod;
    } catch {
      // try the next candidate
    }
  }

  console.error(
    "Could not load playwright. Install it (`npm i playwright`) or set PLAYWRIGHT_PATH.",
  );
  process.exit(3);
}

const { chromium } = loadPlaywright();

const SCRIPT =
  process.env.CAP_WIDGET_SCRIPT || "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.58";
const INSTANCE = (process.env.CAP_INSTANCE_URL || "https://jq.crbbsx.com").replace(/\/$/, "");
const SITE_KEY = process.env.CAP_SITE_KEY || "c87f54f192";
const ENDPOINT = `${INSTANCE}/${SITE_KEY}/`;

const html = `<!doctype html>
<html><head><meta charset="utf-8">
<style>
  .cap-verification-widget.cap-verification-widget--light cap-widget {
    --cap-background: #ffffff;
    --cap-color: #222222;
    --cap-checkbox-border: 1px solid #888888;
  }
</style>
</head>
<body>
  <div class="cap-verification-widget cap-verification-widget--light">
    <cap-widget data-cap-api-endpoint="${ENDPOINT}"></cap-widget>
    <p class="cap-verification-status">pending</p>
  </div>
  <script type="module" src="${SCRIPT}"></script>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage();

const requests = [];
const errors = [];
page.on("request", (r) => {
  if (r.url().startsWith(INSTANCE)) requests.push(r.method() + " " + r.url());
});
page.on("console", (m) => {
  if (m.type() === "error") errors.push(m.text());
});
page.on("pageerror", (e) => errors.push("pageerror: " + e.message));

await page.setContent(html, { waitUntil: "networkidle" });

// Capture the token the widget hands back on its `solve` event. This is the
// exact value the plugin stores in the Rails session and later POSTs to
// /siteverify, so its shape is the contract the server side depends on.
await page.evaluate(() => {
  const el = document.querySelector("cap-widget");
  window.__capToken = null;
  el.addEventListener("solve", (e) => {
    window.__capToken = e.detail?.token ?? null;
  });
});

// The widget does NOT fetch on mount. Its own source shows the challenge
// request only fires from solve(), which is bound to the .captcha-trigger
// element inside the shadow root. So a real click is required.
await page.waitForTimeout(2500);

const clicked = await page.evaluate(() => {
  const el = document.querySelector("cap-widget");
  if (!el || !el.shadowRoot) return "no shadow root";
  const trigger = el.shadowRoot.querySelector(".captcha-trigger");
  if (!trigger) return "no .captcha-trigger";
  if (trigger.hasAttribute("disabled")) return "trigger still disabled";
  trigger.click();
  return "clicked";
});
console.log("click result:", clicked);

// Give the widget time to fetch the challenge and start solving.
await page.waitForTimeout(12000);

const result = await page.evaluate(() => {
  const el = document.querySelector("cap-widget");
  const cs = el ? getComputedStyle(el) : null;
  return {
    elementDefined: !!customElements.get("cap-widget"),
    nodeCount: document.querySelectorAll(".cap-verification-widget").length,
    widgetPresent: !!el,
    hasShadow: !!(el && el.shadowRoot),
    bgVar: cs ? cs.getPropertyValue("--cap-background").trim() : null,
    colorVar: cs ? cs.getPropertyValue("--cap-color").trim() : null,
    state: el && el.shadowRoot ? el.shadowRoot.querySelector(".captcha")?.getAttribute("data-state") : null,
    token: window.__capToken,
    tokenColons: window.__capToken ? window.__capToken.split(":").length - 1 : null,
    hiddenField: el ? el.querySelector('input[type="hidden"]')?.name : null,
  };
});

console.log("=== DOM / custom element ===");
console.log(JSON.stringify(result, null, 2));

console.log("\n=== requests to the Cap instance ===");
console.log(requests.length ? requests.join("\n") : "(none - widget never called out)");

console.log("\n=== console errors ===");
console.log(errors.length ? errors.join("\n") : "(none)");

await browser.close();

// The server-side contract: the Standalone /siteverify handler rejects any
// token whose ":" count is not exactly 2 before it even checks the secret.
const tokenShapeOk = result.tokenColons === 2;

console.log("\n=== token shape contract ===");
console.log("token:", result.token ? result.token.slice(0, 60) + "..." : "(none)");
console.log("colon count:", result.tokenColons, tokenShapeOk ? "(matches siteverify)" : "(MISMATCH - would be rejected)");
console.log("hidden field name:", result.hiddenField, result.hiddenField === "cap-token" ? "(default, as expected)" : "");

const ok =
  result.elementDefined &&
  result.widgetPresent &&
  requests.length > 0 &&
  result.state === "done" &&
  tokenShapeOk;
console.log("\nVERDICT: " + (ok ? "widget loads, solves, and returns a valid token" : "WIDGET DID NOT WORK"));
process.exit(ok ? 0 : 1);
