<template>
  {{#if this.endpoint}}
    <div class="cap-verification-widget" data-cap-theme={{this.theme}}>
      {{! Cap's web component. Inside a <form> it injects a hidden `cap-token`
          field automatically; the `solve` event is our hook for Ember-driven
          forms that do not post the DOM directly. }}
      <cap-widget
        data-cap-api-endpoint={{this.endpoint}}
        data-cap-theme={{this.theme}}
        {{on "solve" this.onSolve}}
        {{on "reset" this.onReset}}
      ></cap-widget>

      {{#if this.args.showStatus}}
        <p class="cap-verification-status {{if this.solved 'is-solved'}}">
          {{#if this.solved}}
            {{i18n "cap_verification.widget_solved"}}
          {{else}}
            {{i18n "cap_verification.widget_pending"}}
          {{/if}}
        </p>
      {{/if}}
    </div>

    <input type="hidden" name="cap_token" value={{this.token}} />
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

  /**
   * Renders a Cap checkbox and mirrors the solved token into a hidden
   * `cap_token` input, which is what the Rails controllers read on submit.
   *
   * Cap docs: https://trycap.dev/zh/guide
   */
  export default class CapWidget extends Component {
    @tracked token = null;

    get solved() {
      return Boolean(this.token);
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
    onSolve(event) {
      this.token = event?.detail?.token ?? null;
      this.args.onSolve?.(this.token);
    }

    @action
    onReset() {
      this.token = null;
      this.args.onReset?.();
    }
  }
</script>
