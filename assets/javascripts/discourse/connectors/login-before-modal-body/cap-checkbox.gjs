<template>
  {{#if this.shouldShow}}
    <CapWidget
      @config={{this.config}}
      @context="login"
      @showStatus={{false}}
    />
  {{/if}}
</template>

<script>
  import Component from "@glimmer/component";
  import { service } from "@ember/service";
  import CapWidget from "discourse/plugins/CloudRail-Cap/discourse/components/cap-widget";

  /**
   * Injects the Cap checkbox above the login form.
   *
   * Outlet: `login-before-modal-body`, declared by core in
   * frontend/discourse/app/templates/login.gjs. This outlet is valid - it was
   * the config lookup that was broken.
   *
   * The config comes from the `site` service, not `siteSettings`: the server
   * publishes it with `add_to_serializer(:site, :cap_verification)`.
   */
  export default class CapLoginConnector extends Component {
    @service site;

    get config() {
      return this.site.cap_verification;
    }

    get shouldShow() {
      return Boolean(
        this.config?.enabled && this.config?.protect_login !== false
      );
    }
  }
</script>
