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
          # The trailing directory name is required, not optional.
          # Discourse derives the plugin's folder name from the clone target
          # and compares it to `# name:` in plugin.rb, warning if they differ.
          # Cloning without it would produce `CloudRail-Cap`, which happens to
          # match here — but pinning it keeps the two guaranteed in sync.
          - git clone https://github.com/liangan772/CloudRail-Cap.git CloudRail-Cap
```

If you prefer to clone manually, name the destination the same way:

```bash
cd /var/discourse
git clone https://github.com/liangan772/CloudRail-Cap.git plugins/CloudRail-Cap
ls plugins/CloudRail-Cap/plugin.rb   # must exist; otherwise you have an extra directory level
```

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
cd /var/discourse/plugins/CloudRail-Cap
git log --oneline -1      # confirm the commit you expect
git pull

# If the plugin lives inside the container instead:
./launcher enter app
cd /var/www/discourse/plugins/CloudRail-Cap
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
   (`/admin/plugins/CloudRail-Cap`) and open the **Setup** tab.
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
| `cap_verification_widget_theme` | `light` | `light`, `dark`, or `auto`. |
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
| `assets/javascripts/.../initializers/cap-verification-admin-plugin-configuration-nav.js` | Registers the plugin's tab on `/admin/plugins/CloudRail-Cap`. |
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

Also note the **location must be the plugin's name** (`CloudRail-Cap`), not an
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
bundle exec rspec plugins/CloudRail-Cap/spec
bundle exec rubocop plugins/CloudRail-Cap
```

The admin screen is written against the `AdminPageHeader` / `DButton` component
set. If core renames those, update
`assets/javascripts/discourse/templates/admin/plugins-capverification.gjs`.

## Licence

MIT
