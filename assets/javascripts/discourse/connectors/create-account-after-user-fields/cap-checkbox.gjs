<template>
  {{#if this.shouldShow}}
    <CapWidget
      @config={{this.config}}
      @context="signup"
      @showStatus={{true}}
    />
  {{/if}}
</template>

<script>
  import Component from "@glimmer/component";
  import { service } from "@ember/service";
  import CapWidget from "discourse/plugins/CloudRail-Cap/discourse/components/cap-widget";

  /**
   * Injects the Cap checkbox into the signup form.
   *
   * Outlet: `create-account-after-user-fields`, declared by core in
   * frontend/discourse/app/templates/signup.gjs. The previous directory name
   * ("create-account") is not an outlet that exists, so nothing ever rendered.
   * Discourse's own captcha plugin uses this same outlet.
   *
   * The config comes from the `site` service, not `siteSettings`: the server
   * publishes it with `add_to_serializer(:site, :cap_verification)`, which
   * lands on the site model. `siteSettings` only carries values from
   * config/settings.yml marked `client: true`, so reading it here silently
   * returned undefined and the widget never appeared.
   */
  export default class CapCreateAccountConnector extends Component {
    @service site;

    get config() {
      return this.site.cap_verification;
    }

    get shouldShow() {
      // Gate on the raw admin switch, NOT on `enabled` (which also requires
      // every credential to be present). Gating on `enabled` made a
      // half-configured site render absolutely nothing, which is
      // indistinguishable from a broken plugin. The widget itself decides what
      // to show.
      return Boolean(
        this.config?.plugin_enabled && this.config?.protect_signup !== false
      );
    }
  }
</script>
