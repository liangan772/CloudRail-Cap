# 部署说明 — cloudrail-cap

三个提交已在本地 `main`（`5bab0bf`、`c36e812`、`af7adb7`），**尚未推送**。
本机非交互环境里 git 推送会卡在凭据管理器，需要你手动执行。

---

## 1. 推送代码

```bash
cd "C:/Users/liangan/WorkBuddy AI/2026-10-02-20-37-57/discourse-cap-verification"
git push origin main
```

推送失败的根因（已定位）：`git-credential-manager.exe get` 在无窗口环境下
挂起 44 秒后超时。`git fetch` 能成功是因为公开仓库读取不需要认证。
如果 push 仍然卡住，先确认凭据：

```bash
git -c http.proxy= -c https.proxy= push origin main
```

---

## 2. ⚠️ 必须重命名插件目录

**这一步不做，CSS 会继续 404。**

插件样式表的目标名 = **目录名**，而 core 的路由限制为小写
（`config/routes.rb` → `name: /[-a-z0-9_]+/`）。目录名带大写时：

- 请求 `/stylesheets/CloudRail-Cap_<digest>.css` 匹配不上路由
- 落到 404 页面，返回 `text/html`
- 浏览器拒绝应用 → `Refused to apply style ... MIME type ('text/html')`

JS bundle 走另一条路由，所以症状是「JS 加载、CSS 静默 404」。

**在服务器上执行：**

```bash
cd /var/docker/plugins          # 或你存放插件的位置

# 如果当前是 CloudRail-Cap
mv CloudRail-Cap cloudrail-cap
```

`plugin.rb` 里的 `# name:` 已经是 `cloudrail-cap`，两者必须一致。

---

## 3. 重新构建

```bash
cd /var/docker
./launcher rebuild app
```

注意：**单纯 rebuild 不会更新插件代码**，必须先从远端 `git pull`。

---

## 4. 验证部署成功

```bash
# A) 插件已加载且配置正确
curl -s https://www.crbbsx.com/site.json | \
  python -c "import json,sys; print(json.load(sys.stdin)['cap_verification'])"
```

应看到：

```json
{
  "plugin_enabled": true,
  "configured": true,
  "enabled": true,
  "protect_signup": true,
  "protect_login": true,
  "instance_url": "https://jq.crbbsx.com",
  "site_key": "c87f54f192",
  "widget_theme": "auto",
  "script_url": "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.58"
}
```

```bash
# B) 样式表返回 200 + text/css（不是 404 + text/html）
curl -sI "https://www.crbbsx.com/stylesheets/cloudrail-cap_<digest>.css" | head -3
```

在浏览器控制台执行：

```js
// C) 组件已注册
customElements.get("cap-widget")            // 应为 function，不再是 undefined

// D) 页面上有节点
document.querySelectorAll(".cap-verification-widget").length   // 注册/登录页应 >= 1

// E) 无编译错误
// 控制台不应再出现 "Compile error: Error: Parse Error at ..."
```

### F) 伪造提交必须被拒（最关键的一项）

前面 5 项只证明「前端渲染正常」。这一项才证明**服务端真的在拦人**。
直接对着注册接口发请求，不带 token：

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" \
  -X POST "https://www.crbbsx.com/u.json" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"name":"probe","email":"probe@example.com","password":"Zx9-Qw2-Kp7-Vt4","username":"probe1"}'
```

**必须是 `HTTP 403`。** 如果返回 `HTTP 200`，说明服务端校验根本没接上——
这时前面 5 项再漂亮也没有意义。

---

## 5. 本次修复了什么

| # | 问题 | 根因 | 证据 |
|---|---|---|---|
| 1 | 组件完全不渲染 | 3 个 `.gjs` 用了 `<template>` + 独立 `<script>` 的非法写法，`js_compiler.rb` 把**整个 bundle** 替换成 `throw new Error(...)` | `content-tag` 在旧版本上逐字节复现 `Parse Error at ...:48:11` |
| 2 | CSS 404 / MIME 错误 | 插件目录名大写，路由限制为小写 | 同一 digest 下 `common_*.css` → 200，`Common_*.css` → 404 |
| 3 | 「测试连接」永远失败 | 旧 probe 发的 token 冒号数不是 2，被 `siteverify` 的 400 挡在密钥校验之前 | 实盘：2 冒号 → 403（到达密钥层），0/1 冒号 → 400 |
| 4 | 深色论坛上是一块白块 | widget 在 shadow root 内，不继承外部配色；内置 fallback 硬编码浅色，且无 `prefers-color-scheme` | 浏览器实测深色页面下背景 `rgb(253,253,253)` |
| 5 | 中文论坛显示英文 | widget 硬编码英文，只认 `data-cap-i18n-*` 属性 | 浏览器实测接入后渲染出「点击验证您是人类」 |
| 6 | **不带 token 也能注册成功（HTTP 200）** | `add_to_class(:users_controller, :create)` 里的 `super()` 永远抛异常，拦截逻辑从未生效 | Ruby 3.3 原样复现：`NoMethodError: super: no superclass method \`create_without_enable_check'\`；裸 `super` → `RuntimeError: implicit argument passing of super ... not supported` |

另外修掉：脚本 URL 未固定版本、`.cap-verification-misconfigured` 选择器
永远匹配不到、后台组件给 `this.args.model` 赋值（严格 ESM 下抛错）。

---

## 6. 验证结果

静态：6/6 `.gjs`、9/9 Ruby、5/5 YAML、SCSS 编译通过、
locale 对齐（client 57/57、server 58/58）。

浏览器（Chromium + 线上实例）：

| 脚本 | 验证内容 | 结果 |
|---|---|---|
| `scripts/browser/widget-solve.mjs` | 元素升级、点击求解 `state="done"`、发出 challenge+redeem、token 恰好 2 冒号 | 通过 |
| `scripts/browser/widget-theme.mjs` | 3 模式 × 浅/深论坛 = 6 项 | 6/6 通过 |
| `scripts/browser/widget-i18n.mjs` | 中文标签渲染、无英文泄漏 | 4/4 通过 |

`scripts/probe-live-cap.rb`：实盘 4 种失败场景全部 fail-closed，网络异常也 fail-closed。

---

## 7. 可选：如果 jsDelivr 在你的网络不可达

站点在中国大陆，jsDelivr 部分区域被屏蔽。若访客加载不出组件，
把 widget 自托管，然后在后台改 `cap_verification_widget_script_url`：

```bash
curl -sL "https://cdn.jsdelivr.net/npm/@cap.js/widget@0.1.58/cap.min.js" \
  -o /var/docker/shared/standalone/public/cap-widget-0.1.58.min.js
```

然后设为 `https://www.crbbsx.com/cap-widget-0.1.58.min.js`。
Cap 实例自带的 `/assets/widget.js` 也可以。
