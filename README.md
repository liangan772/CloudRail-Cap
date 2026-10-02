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

## Setup

1. Start the Cap server and open its console (see the
   [quick start](https://trycap.dev/zh/guide#_1-%E8%BF%90%E8%A1%8C%E6%9C%8D%E5%8A%A1%E7%AB%AF)).
2. Create a **site key** and copy both the *site key* and the *secret key*.
3. In Discourse go to **Admin → Plugins → Cap Verification**.
4. Fill in the instance URL, site key and secret key. The instance URL must be
   publicly reachable by visitors — `localhost` will not work.
5. Click **Test connection**, then enable the plugin and save.

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

```
browser                    Discourse                    Cap server
   |  tick checkbox            |                             |
   |-------------------------->|                             |
   |  hidden cap_token         |                             |
   |   POST /signup            |                             |
   |-------------------------->|  POST /{site_key}/siteverify|
   |                           |---------------------------->|
   |                           |        { success: true }    |
   |                           |<----------------------------|
   |    account created        |                             |
   |<--------------------------|                             |
```

`UsersController#create` and `SessionController#create` are extended in
`plugin.rb`. Before the core action runs, `DiscourseCap::Verify.enforce!` redeems
the token. Cap tokens are single-use, so a captured token cannot be replayed.

### Key files

| Path | Role |
| --- | --- |
| `plugin.rb` | Entry point: settings, controller extensions, admin route. |
| `lib/discourse_cap/verify.rb` | Token redemption, throttling, bypass rules. |
| `lib/discourse_cap/config.rb` | Single source of truth for "is Cap usable?" plus the client payload. |
| `app/controllers/discourse_cap/admin_controller.rb` | Admin settings API and connection test. |
| `assets/javascripts/.../components/cap-widget.gjs` | The checkbox, mirrors the token into `cap_token`. |
| `assets/javascripts/.../connectors/*/cap-checkbox.gjs` | Injects the widget into the signup and login outlets. |
| `assets/javascripts/.../templates/admin/plugins/cap-verification.gjs` | Admin settings screen. |

## Development

```bash
# From your Discourse checkout
bundle exec rspec plugins/CloudRail-Cap/spec
bundle exec rubocop plugins/CloudRail-Cap
```

The admin screen is written against the `AdminPageHeader` / `DButton` component
set. If core renames those, update
`assets/javascripts/discourse/templates/admin/plugins/cap-verification.gjs`.

## Licence

MIT
