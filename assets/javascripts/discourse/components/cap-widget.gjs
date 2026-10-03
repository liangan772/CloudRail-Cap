import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
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
 *
 * NOTE ON FILE FORMAT: this is a single-file `.gjs` component, so the
 * <template> tag lives *inside* the class body. A `<template>...</template>`
 * followed by a separate `<script>...</script>` block is NOT valid gjs - it
 * fails to parse and takes the whole plugin bundle down with it.
 */
export default class CapWidget extends Component {
  @service currentUser;

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
    return this.config?.widget_theme || "auto";
  }

  /**
   * Theme class for the wrapper. Cap's widget has no theme attribute — it is
   * themed through CSS custom properties, so the class is what actually
   * recolours it (see cap-verification.scss). "auto" defers to the forum's own
   * colour scheme rather than the OS preference, so the checkbox matches the
   * surrounding page.
   */
  get themeClass() {
    return `cap-verification-widget--${this.theme}`;
  }

  /**
   * The plugin is switched on but the credentials are incomplete, so there is
   * nothing to verify against. Only staff are told - showing this to every
   * visitor would just look like a broken site. This is what makes a
   * half-configured install diagnosable instead of silently blank.
   */
  get misconfigured() {
    return (
      Boolean(this.config?.plugin_enabled) &&
      !this.config?.configured &&
      Boolean(this.currentUser?.staff)
    );
  }

  get endpoint() {
    const instance = this.config?.instance_url?.replace?.(/\/$/, "");
    const siteKey = this.config?.site_key;
    if (!instance || !siteKey || !this.config?.enabled) {
      return null;
    }
    return `${instance}/${siteKey}/`;
  }

  /**
   * Labels for the strings Cap's widget hard-codes in English.
   *
   * The widget resolves every label through
   * `getAttribute("data-cap-i18n-" + key) || default`, so these attributes are
   * the only way to translate it. Without them a Chinese forum still shows
   * "Verify you're human".
   *
   * The keys below are exactly the ones the widget asks for; they were read
   * out of its source rather than the docs, because the docs list only some of
   * them (group-aria-label is undocumented).
   */
  get labels() {
    return {
      initialState: i18n("cap_verification.widget_initial_state"),
      verifyingLabel: i18n("cap_verification.widget_verifying_label"),
      solvedLabel: i18n("cap_verification.widget_solved_label"),
      errorLabel: i18n("cap_verification.widget_error_label"),
      troubleshootingLabel: i18n("cap_verification.widget_troubleshooting_label"),
      wasmDisabled: i18n("cap_verification.widget_wasm_disabled"),
      verifyAriaLabel: i18n("cap_verification.widget_verify_aria_label"),
      verifyingAriaLabel: i18n("cap_verification.widget_verifying_aria_label"),
      verifiedAriaLabel: i18n("cap_verification.widget_verified_aria_label"),
      requiredLabel: i18n("cap_verification.widget_required_label"),
      errorAriaLabel: i18n("cap_verification.widget_error_aria_label"),
      groupAriaLabel: i18n("cap_verification.widget_group_aria_label"),
    };
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

  <template>
    {{#if this.endpoint}}
      <div class="cap-verification-widget {{this.themeClass}}">
        {{! Cap's web component. The `solve` event is our hook: we redeem the
            token straight away rather than trying to submit it with the form.

            Note there is deliberately no `data-cap-theme` attribute - Cap's
            widget does not implement one. Theming is done with CSS custom
            properties from the wrapper class above.

            The data-cap-i18n-* attributes override the widget's hard-coded
            English labels; see the `labels` getter. }}
        <cap-widget
          data-cap-api-endpoint={{this.endpoint}}
          data-cap-i18n-initial-state={{this.labels.initialState}}
          data-cap-i18n-verifying-label={{this.labels.verifyingLabel}}
          data-cap-i18n-solved-label={{this.labels.solvedLabel}}
          data-cap-i18n-error-label={{this.labels.errorLabel}}
          data-cap-i18n-troubleshooting-label={{this.labels.troubleshootingLabel}}
          data-cap-i18n-wasm-disabled={{this.labels.wasmDisabled}}
          data-cap-i18n-verify-aria-label={{this.labels.verifyAriaLabel}}
          data-cap-i18n-verifying-aria-label={{this.labels.verifyingAriaLabel}}
          data-cap-i18n-verified-aria-label={{this.labels.verifiedAriaLabel}}
          data-cap-i18n-required-label={{this.labels.requiredLabel}}
          data-cap-i18n-error-aria-label={{this.labels.errorAriaLabel}}
          data-cap-i18n-group-aria-label={{this.labels.groupAriaLabel}}
          {{on "solve" this.onSolve}}
          {{on "reset" this.onReset}}
        ></cap-widget>

        {{#if @showStatus}}
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
}
