<template>
  {{#if this.shouldShow}}
    <CapWidget @config={{this.config}} @showStatus={{false}} />
  {{/if}}
</template>

<script>
  import Component from "@glimmer/component";
  import { service } from "@ember/service";
  import CapWidget from "discourse/plugins/CloudRail-Cap/discourse/components/cap-widget";

  /**
   * Injects the Cap checkbox above the login form.
   *
   * Connector path:
   *   assets/javascripts/discourse/connectors/login-before-modal-body/cap-checkbox.gjs
   *
   * The `login-before-modal-body` outlet is defined by core in the login
   * template, so no core patching is required.
   */
  export default class CapLoginConnector extends Component {
    @service siteSettings;

    get config() {
      return this.siteSettings.cap_verification;
    }

    get shouldShow() {
      return Boolean(
        this.config?.enabled && this.config?.protect_login !== false
      );
    }
  }
</script>
