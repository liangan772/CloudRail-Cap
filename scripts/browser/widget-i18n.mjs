/**
 * Verifies that the data-cap-i18n-* attributes actually reach the widget and
 * replace its hard-coded English labels.
 *
 * The widget renders its label into the shadow root, so we read the shadow
 * text back after setting the attributes exactly as the component does.
 *
 * Usage:
 *   CAP_INSTANCE_URL=https://cap.example.com CAP_SITE_KEY=abc123 \
 *   node scripts/browser/widget-i18n.mjs
 *
 * Requires playwright. Resolution order: PLAYWRIGHT_PATH, then the package name.
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

// The Chinese strings, as the plugin's zh_CN locale defines them.
const ZH = {
  "data-cap-i18n-initial-state": "点击验证您是人类",
  "data-cap-i18n-verifying-label": "正在验证……",
  "data-cap-i18n-solved-label": "验证通过",
  "data-cap-i18n-error-label": "验证出错",
  "data-cap-i18n-troubleshooting-label": "排查问题",
  "data-cap-i18n-wasm-disabled": "启用 WASM 可显著加快验证速度",
  "data-cap-i18n-verify-aria-label": "点击验证您是人类",
  "data-cap-i18n-verifying-aria-label": "正在验证，请稍候",
  "data-cap-i18n-verified-aria-label": "已验证",
  "data-cap-i18n-required-label": "请先完成人机验证",
  "data-cap-i18n-error-aria-label": "发生错误，请重试",
  "data-cap-i18n-group-aria-label": "Cap 人机验证",
};

const attrs = Object.entries(ZH)
  .map(([k, v]) => `${k}="${v}"`)
  .join("\n          ");

const html = `<!doctype html>
<html><head><meta charset="utf-8"></head>
<body>
  <div class="cap-verification-widget">
    <cap-widget
          data-cap-api-endpoint="${ENDPOINT}"
          ${attrs}
    ></cap-widget>
  </div>
  <script type="module" src="${SCRIPT}"></script>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent(html, { waitUntil: "load" });
await page.waitForFunction(() => !!customElements.get("cap-widget"), { timeout: 30000 }).catch(() => {});
await page.waitForTimeout(1500);

const r = await page.evaluate(() => {
  const el = document.querySelector("cap-widget");
  const root = el?.shadowRoot;
  if (!root) return { error: "no shadow root" };
  const trigger = root.querySelector(".captcha-trigger");
  const label = root.querySelector(".label.active");
  return {
    triggerAriaLabel: trigger?.getAttribute("aria-label"),
    visibleLabel: label?.textContent?.trim(),
    groupAriaLabel: root.querySelector(".captcha")?.getAttribute("aria-label"),
    shadowText: (root.textContent || "").trim().slice(0, 80),
  };
});

await browser.close();

console.log("=== widget labels with zh_CN attributes ===");
console.log(JSON.stringify(r, null, 2));

if (r.error) {
  console.log("\nVERDICT: INCONCLUSIVE - " + r.error);
  process.exit(2);
}

const checks = [
  ["visible label is Chinese", r.visibleLabel === "点击验证您是人类"],
  ["trigger aria-label is Chinese", r.triggerAriaLabel === "点击验证您是人类"],
  ["group aria-label is Chinese", r.groupAriaLabel === "Cap 人机验证"],
  ["no English leaked through", !/Verify you're human/i.test(r.shadowText)],
];

console.log("");
let ok = true;
for (const [name, pass] of checks) {
  console.log("  " + name + " -> " + (pass ? "OK" : "FAIL"));
  if (!pass) ok = false;
}
console.log("\nVERDICT: " + (ok ? "the widget is fully localised" : "SOME LABELS ARE STILL ENGLISH"));
process.exit(ok ? 0 : 1);
