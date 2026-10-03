# CloudRail-Cap

Self-hosted human verification (CAPTCHA) for Discourse, powered by
[Cap](https://trycap.dev/zh/guide) — a proof-of-work CAPTCHA with no Google, no
tracking and no per-request billing.

Visitors tick a checkbox, the proof-of-work is computed silently in the browser,
and your own Cap server verifies the resulting single-use token. The plugin adds
the challenge to the signup and login forms and ships a dedicated admin settings
screen.

## Features

- Cap checkbox on **signup** and **login**, each independently toggleable.
- Server-side token verification against `POST {instance}/{site_key}/siteverify`.
  A challenge the server cannot verify is never shown.
- Staff and high-trust-level users are exempt so they are never interrupted.
- Failed verifications are throttled per IP and written to an audit table.
- Admin screen at `/admin/plugins/cap-verification` with a live status badge,
  a "Test connection" button and setup instructions. All values are also
  editable under **Admin → Settings → Plugins**.
- 100% `.gjs` frontend. No `.hbs` files, so the plugin is unaffected by the
  [`.hbs` deprecation](https://meta.discourse.org/t/deprecating-hbs-file-extension-in-themes-and-plugins/398896)
  that removes support after the 2026.7 ESR.

## Requirements

- Discourse `3.3.0` or newer (`.gjs` component support).
- A reachable Cap server. The fastest route is the
  [Cap Standalone](https://trycap.dev/zh/standalone/) container:
  it serves the API, hosts a console for managing site keys, and is
  reCAPTCHA-`/siteverify` compatible.

## Installation

Add the repository to your `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          # The trailing directory name is required, not optional, and it MUST
          # BE LOWERCASE. Discourse derives the plugin's stylesheet target from
          # this directory name, and core serves stylesheets through a route
          # constrained to lowercase:
          #
          #   get "stylesheets/:name", constraints: { name: /[-a-z0-9_]+/ }
          #
          # Cloning without the target would produce `CloudRail-Cap`. The
          # browser would then request `/stylesheets/CloudRail-Cap_<digest>.css`,
          # the route would not match, and the request would fall through to the
          # 404 page — returning HTML where CSS was expected:
          #
          #   Refused to apply style ... MIME type ('text/html') is not a
          #   supported stylesheet MIME type
          #
          # The JS bundle uses a different route, so it keeps working. The
          # result is a plugin whose JavaScript loads and whose CSS silently
          # 404s.
          - git clone https://github.com/liangan772/CloudRail-Cap.git cloudrail-cap
```

If you prefer to clone manually, name the destination the same way:

```bash
cd /var/discourse
git clone https://github.com/liangan772/CloudRail-Cap.git plugins/cloudrail-cap
ls plugins/cloudrail-cap/plugin.rb   # must exist; otherwise you have an extra directory level
```

> **Upgrading an existing install?** The directory was previously
> `CloudRail-Cap`. Rename it before rebuilding, or the stylesheet keeps 404ing:
>
> ```bash
> cd /var/discourse/plugins
> git -C CloudRail-Cap remote -v          # confirm it is this repo
> mv CloudRail-Cap cloudrail-cap
> git -C cloudrail-cap pull
> ```
>
> A stale `CloudRail-Cap` directory left behind will be loaded as a second copy
> of the plugin. Remove it rather than leaving both.

Then rebuild:

```bash
./launcher rebuild app
```

### Updating an existing install

**`./launcher rebuild app` on its own does not update the plugin.** The
`after_code` hook above runs `git clone`, and once the directory exists the clone
fails — nothing is pulled. Rebuilding only recompiles whatever source is already
there, so a rebuild after a `git push` can silently keep running the old code.

Pull first, then rebuild:

```bash
# If you cloned into the host's plugins directory:
cd /var/discourse/plugins/cloudrail-cap
git log --oneline -1      # confirm the commit you expect
git pull

# If the plugin lives inside the container instead:
./launcher enter app
cd /var/www/discourse/plugins/cloudrail-cap
git log --oneline -1
git pull
exit

cd /var/discourse
./launcher rebuild app
```

To confirm the new code is live, open `/site.json` and look at
`cap_verification`. The current payload contains `plugin_enabled` and
`configured`; if those keys are absent you are still running an older revision.

## Setup

1. Start the Cap server and open its console (see the
   [quick start](https://trycap.dev/zh/guide#_1-%E8%BF%90%E8%A1%8C%E6%9C%8D%E5%8A%A1%E7%AB%AF)).
2. Create a **site key** and copy both the *site key* and the *secret key*.
3. In Discourse go to **Admin → Plugins → Cap Verification**
   (`/admin/plugins/cloudrail-cap`) and open the **Setup** tab.
4. Fill in the instance URL, site key and secret key. The instance URL must be
   publicly reachable by visitors — `localhost` will not work.
5. Click **Test connection**, then enable the plugin and save.

> The plugin's **Settings** tab is Discourse's own generated page for the site
> settings; the **Setup** tab is this plugin's form. Both edit the same values.

> The **secret key** is not the console's `ADMIN_KEY`. Mixing these up is the
> most common configuration mistake.

## Settings

| Setting | Default | Purpose |
| --- | --- | --- |
| `cap_verification_enabled` | `false` | Master switch. |
| `cap_verification_instance_url` | `""` | Public base URL of your Cap server. |
| `cap_verification_site_key` | `""` | Public site key, sent to the browser. |
| `cap_verification_secret_key` | `""` | Server-side secret. Never sent to the client. |
| `cap_verification_widget_script_url` | jsDelivr | Where `cap-widget` loads from. Point at a self-hosted copy for maximum privacy. |
| `cap_verification_widget_theme` | `auto` | `auto` follows the forum's colour scheme; `light` / `dark` pin the widget and override the forum. |
| `cap_verification_protect_signup` | `true` | Challenge the signup form. |
| `cap_verification_protect_login` | `true` | Challenge the login form. |
| `cap_verification_skip_for_staff` | `true` | Never challenge staff. |
| `cap_verification_min_trust_level` | `0` | Exempt logged-in users at or above this TL. `0` = challenge everyone. |
| `cap_verification_max_attempts` | `10` | Failed verifications per IP per minute before throttling. |
| `cap_verification_timeout_seconds` | `8` | Timeout for the verification request. |

## How it works

The token is redeemed **when the challenge is solved**, not when the form is
submitted, because it cannot travel with the form. Discourse builds the signup
and login payloads explicitly in JS:

```js
// frontend/discourse/app/models/user.js
const data = { name, email, password, username, ... };
ajax(userPath(), { data, type: "POST" });
```

so a hidden form field is never sent. And there is no plugin hook for the login
flow at all — `BEHAVIOR_TRANSFORMERS` contains `create-account` but nothing for
login, and `plugin-api` exposes no login/session API.

```
browser                    Discourse                    Cap server
   |  solve challenge          |                             |
   |  POST /cap-verification/verify                          |
   |-------------------------->|  POST /{site_key}/siteverify|
   |                           |---------------------------->|
   |                           |        { success: true }    |
   |                           |<----------------------------|
   |                           |  session[:cap_verification_verified]
   |    { success: true }      |                             |
   |<--------------------------|                             |
   |  POST /signup             |                             |
   |-------------------------->|  reads the session flag     |
   |    account created        |  (single-use, 15 min TTL)   |
   |<--------------------------|                             |
```

`UsersController#create` and `SessionController#create` are extended in
`plugin.rb`. They call `DiscourseCap::Verify.enforce_session!`, which consumes the
session flag set by `/cap-verification/verify`. Cap tokens are single-use, and the
flag is cleared on use, so neither can be replayed. Discourse's own captcha plugin
verifies out-of-band and keeps the result server-side in the same way.

### Key files

| Path | Role |
| --- | --- |
| `plugin.rb` | Entry point: settings, controller extensions, admin route. |
| `lib/discourse_cap/verify.rb` | Token redemption, session flag, throttling, bypass rules. |
| `lib/discourse_cap/config.rb` | Single source of truth for "is Cap usable?" plus the client payload. |
| `app/controllers/discourse_cap/verification_controller.rb` | Signed-out endpoint that redeems the token. |
| `app/controllers/discourse_cap/admin_controller.rb` | Settings API (`/cap-verification/*`) and connection test. |
| `assets/javascripts/.../components/cap-widget.gjs` | The checkbox; redeems the token on solve. |
| `assets/javascripts/.../connectors/create-account-after-user-fields/` | Signup outlet. |
| `assets/javascripts/.../connectors/login-before-modal-body/` | Login outlet. |
| `assets/javascripts/.../cap-verification-route-map.js` | Mounts the plugin's admin route on `admin.adminPlugins.show`. |
| `assets/javascripts/.../initializers/cap-verification-admin-plugin-configuration-nav.js` | Registers the plugin's tab on `/admin/plugins/cloudrail-cap`. |
| `admin/assets/javascripts/.../routes/admin-plugins/show/cap-verification.js` | Loads the settings payload. |
| `admin/assets/javascripts/.../templates/admin-plugins/show/cap-verification.gjs` | Route template; renders the component below. |
| `admin/assets/javascripts/.../components/cap-verification-settings.gjs` | The settings form: fields, save, test connection. |
| `config/locales/client.*.yml` | Frontend strings. **Must be nested under `js:`** or lookups fail. |
| `config/locales/server.*.yml` | Site-setting labels and server-side error messages. |

Note the split: frontend code that runs in the main app lives under
`assets/javascripts/`, while admin-page code lives under `admin/assets/javascripts/`.

### Frontend troubleshooting

**The checkbox does not appear.** Two causes, both easy to hit:

1. **Wrong config source.** The server publishes the widget config with
   `add_to_serializer(:site, :cap_verification)`, which lands on the **`site`**
   model — read it as `site.cap_verification`. `siteSettings` only carries values
   from `config/settings.yml` marked `client: true`, so reading it returns
   `undefined` and the connector renders nothing.
2. **Outlet that does not exist.** The connector's directory name must be a real
   outlet. Valid signup outlets are `create-account-before-modal-body`,
   `create-account-after-user-fields`, `create-account-after-modal-footer`;
   valid login outlets are `login-before-modal-body`, `login-header-bottom`.
   Check `frontend/discourse/app/templates/signup.gjs` and `login.gjs` for the
   current list — an unknown outlet is silently ignored.

**The checkbox appears but every submission is rejected.** The token never
reached the server. Do not mirror it into a hidden input; redeem it from the
widget as described above.

## Troubleshooting

### The widget never appears, and `app.js` reports a plugin compile error

```text
Failed to load plugin CloudRail-Cap from .../CloudRail-Cap_main-<hash>.digested.js
Error: [PLUGIN CloudRail-Cap] Compile error: Error: Parse Error at
discourse/plugins/CloudRail-Cap/.../cap-checkbox.gjs:48:11: 48:11
```

The plugin's JavaScript bundle failed to build, so **nothing** in the plugin
loads — no connectors, no initializer, no widget. Fetch the bundle and you will
find it is a single statement:

```js
throw new Error("[PLUGIN ...] Compile error: ...");
```

Core does that on purpose (`lib/plugin/js_compiler.rb`) so a broken build fails
loudly rather than silently shipping half a plugin.

The cause is a `.gjs` file in the wrong shape. A `.gjs` file is **one** ES
module: the `<template>` tag must be either the operand of `export default`, or
a member inside `export default class { ... }`. The `<template>...</template>`
followed by a separate `<script>...</script>` block is **not** valid — it is the
one-file `.gjs` equivalent of a `.hbs`/`.js` pair, and it does not parse.

```gjs
// WRONG - fails the whole bundle
<template>
  <div>hi</div>
</template>

<script>
  export default class Foo {}
</script>
```

```gjs
// RIGHT
export default class Foo {
  <template>
    <div>hi</div>
  </template>
}
```

The reported line is the closing `</script>`, which makes the message look like
a stray-tag problem rather than a structural one.

`scripts/check-gjs.mjs` catches this before you rebuild. It uses `content-tag`,
the same preprocessor core's asset pipeline uses, so it reports the identical
error:

```bash
npm install --no-save content-tag     # once
node scripts/check-gjs.mjs .
```

### `Refused to apply style ... MIME type ('text/html') is not a supported stylesheet MIME type`

The plugin's CSS is 404ing. Core serves stylesheets through a route constrained
to lowercase:

```ruby
# config/routes.rb
get "stylesheets/:name" => "stylesheets#show",
    constraints: { name: /[-a-z0-9_]+/, format: "css" }
```

The requested name is `<plugin directory>_<digest>.css`. If the directory
contains an uppercase letter the route does not match, the request falls through
to the 404 page, and the browser receives HTML where it expected CSS — hence the
MIME error rather than a clean 404.

Confirm it in one request:

```bash
curl -sI "https://your-forum/stylesheets/cloudrail-cap_<digest>.css" | head -2
# 404 + text/html  -> the directory name is wrong
# 200 + text/css   -> correct
```

Fix by renaming the plugin directory to `cloudrail-cap` (see
[Installation](#installation)). The directory name is what matters, not the
repository name and not the `# name:` line on its own — keep all three
lowercase and consistent.

### `Test connection` reports a failure on a working server

Cap validates the token's *shape* before it looks at the secret:

```js
// standalone/src/siteverify.js
if (response.split(":").length !== 3) {
  return { success: false, error: "Missing required parameters" };
}
```

So a probe token without exactly two colons always returns HTTP 400, regardless
of whether the credentials are correct. The probe must send
`<site_key>:<id>:<secret>`, which is what `Verify.probe_token` does. With good
credentials the server then answers `404 Token not found` — which is the healthy
result, because the probe token is deliberately fake.

If the dashboard says the credentials are wrong, check that you pasted the
**secret key** (`sk-...`) and not the **admin key**. They are different values
and mixing them up is the single most common setup mistake.

### `Unable to configure link to '...'. Ensure ad-blockers are disabled and try reloading the page.`

This is core's `admin.plugins.broken_route`. Despite the wording it is never an
ad blocker — it means Discourse could not resolve the plugin's admin route in
the frontend router:

```js
// frontend/discourse/app/lib/admin-utilities.js
export function adminRouteValid(router, adminRoute) {
  try {
    if (adminRoute.use_new_show_route) {
      router.urlFor(adminRoute.full_location, adminRoute.location);
    } else {
      router.urlFor(adminRoute.full_location);
    }
    return true;
  } catch {
    return false;
  }
}
```

`full_location` is `adminPlugins.show` when `add_admin_route` is called with
`use_new_show_route: true`, and `adminPlugins.<location>` when it is `false`.
**Use `true`.** `adminPlugins.show` is a core route, so the link always
resolves. The `false` form requires the plugin to mount `adminPlugins.<location>`
itself, and the legacy mount point (`resource: "admin.adminPlugins"`) is no
longer supported — mounting there fails silently and the route never exists.
No plugin in the Discourse repo still uses `false`.

Two things to check:

1. `add_admin_route` uses `use_new_show_route: true`.
2. The route map mounts on `resource: "admin.adminPlugins.show"`, and its
   `this.route(...)` name matches the nav entry's route
   (`adminPlugins.show.cap-verification`).

Also note the **location must be the plugin's name** (`cloudrail-cap`), not an
arbitrary slug. The page is loaded with:

```ruby
# app/controllers/admin/plugins_controller.rb
plugin = Discourse.plugins_by_name[params[:plugin_id]]
```

and `plugins_by_name` is keyed by plugin name, so anything else 404s on
`/admin/plugins/<location>.json`.

If the `'...'` part shows a raw key such as `[zh_CN.cap_verification.admin.title]`
rather than a readable name, the label is also untranslated — see below.

### Labels show as `[zh_CN.something]` instead of text

Two causes, both easy to hit:

1. **Missing `js:` wrapper.** Client locale files must nest their keys under
   `js:`, because the contents are merged into the JS bundle:

   ```yaml
   en:
     js:
       cap_verification:
         admin:
           title: "Cap Verification"
   ```

2. **Missing translation for the active locale.** Discourse ships `en` here plus
   `zh_CN`. If your site runs another locale, add a `client.<locale>.yml` with the
   same key set (the `en` file is the reference).

## Development

```bash
# From your Discourse checkout
bundle exec rspec plugins/cloudrail-cap/spec
bundle exec rubocop plugins/cloudrail-cap
```

The admin screen is written against the `AdminPageHeader` / `DButton` component
set. If core renames those, update
`assets/javascripts/discourse/templates/admin/plugins-capverification.gjs`.

## Licence

MIT
