<template>
  {{#if this.shouldShow}}
    <CapWidget @config={{this.config}} @showStatus={{true}} />
  {{/if}}
</template>

<script>
  import Component from "@glimmer/component";
  import { service } from "@ember/service";
  import CapWidget from "discourse/plugins/discourse-cap-verification/discourse/components/cap-widget";

  /**
   * Injects the Cap checkbox into the signup form.
   *
   * Connector path:
   *   assets/javascripts/discourse/connectors/create-account/cap-checkbox.gjs
   *
   * Uses the modern `.gjs` format - `.hbs` connectors are deprecated, see
   * https://meta.discourse.org/t/deprecating-hbs-file-extension-in-themes-and-plugins/398896
   */
  export default class CapCreateAccountConnector extends Component {
    @service siteSettings;

    get config() {
      return this.siteSettings.cap_verification;
    }

    get shouldShow() {
      return Boolean(
        this.config?.enabled && this.config?.protect_signup !== false
      );
    }
  }
</script>
