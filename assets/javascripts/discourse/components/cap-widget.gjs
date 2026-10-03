<template>
  {{#if this.endpoint}}
    <div class="cap-verification-widget" data-cap-theme={{this.theme}}>
      {{! Cap's web component. The `solve` event is our hook: we redeem the
          token straight away rather than trying to submit it with the form. }}
      <cap-widget
        data-cap-api-endpoint={{this.endpoint}}
        data-cap-theme={{this.theme}}
        {{on "solve" this.onSolve}}
        {{on "reset" this.onReset}}
      ></cap-widget>

      {{#if this.args.showStatus}}
        <p class="cap-verification-status {{this.statusClass}}">
          {{this.statusMessage}}
        </p>
      {{/if}}
    </div>
  {{else if this.misconfigured}}
    <div class="cap-verification-widget cap-verification-misconfigured">
      <span class="cap-verification-warning">
        {{i18n "cap_verification.widget_misconfigured"}}
      </span>
    </div>
  {{/if}}
</template>

<script>
  import Component from "@glimmer/component";
  import { tracked } from "@glimmer/tracking";
  import { action } from "@ember/object";
  import { on } from "@ember/modifier";
  import { ajax } from "discourse/lib/ajax";
  import { i18n } from "discourse-i18n";

  /**
   * Renders a Cap checkbox and redeems the solved token server-side.
   *
   * The token is deliberately NOT mirrored into a hidden input. Discourse
   * builds the signup and login payloads explicitly in JS:
   *
   *   // frontend/discourse/app/models/user.js
   *   const data = { name, email, password, username, ... };
   *   ajax(userPath(), { data, type: "POST" });
   *
   * so a hidden field in the DOM is never sent. And there is no plugin hook for
   * the login flow at all - BEHAVIOR_TRANSFORMERS has "create-account" but
   * nothing for login.
   *
   * So verification happens when the visitor solves the challenge: we POST the
   * token to /cap-verification/verify, which redeems it against Cap and records
   * the result in the Rails session. The signup and login controllers then only
   * check that flag. Discourse's own captcha plugin verifies out-of-band the
   * same way.
   *
   * Cap docs: https://trycap.dev/zh/guide
   */
  export default class CapWidget extends Component {
    /** idle | verifying | verified | failed */
    @tracked state = "idle";

    get solved() {
      return this.state === "verified";
    }

    get statusClass() {
      if (this.state === "verified") {
        return "is-solved";
      }
      return this.state === "failed" ? "is-failed" : "";
    }

    get statusMessage() {
      const key = {
        verifying: "cap_verification.widget_verifying",
        verified: "cap_verification.widget_solved",
        failed: "cap_verification.widget_failed",
      }[this.state];

      return i18n(key || "cap_verification.widget_pending");
    }

    get config() {
      return this.args.config;
    }

    get theme() {
      return this.config?.widget_theme || "light";
    }

    /** True when the plugin is on but the admin has not finished setup. */
    get misconfigured() {
      return Boolean(this.config?.enabled) && !this.endpoint;
    }

    get endpoint() {
      const instance = this.config?.instance_url?.replace?.(/\/$/, "");
      const siteKey = this.config?.site_key;
      if (!instance || !siteKey || !this.config?.enabled) {
        return null;
      }
      return `${instance}/${siteKey}/`;
    }

    @action
    async onSolve(event) {
      const token = event?.detail?.token;
      if (!token) {
        return;
      }

      this.state = "verifying";

      try {
        const result = await ajax("/cap-verification/verify", {
          type: "POST",
          data: { token, context: this.args.context || "signup" },
        });
        this.state = result?.success ? "verified" : "failed";
      } catch {
        this.state = "failed";
      }

      this.args.onSolve?.(this.state === "verified" ? token : null);
    }

    @action
    onReset() {
      this.state = "idle";
      this.args.onReset?.();
    }
  }
</script>
