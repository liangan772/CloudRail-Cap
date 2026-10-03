import Component from "@glimmer/component";
import { service } from "@ember/service";
import CapWidget from "discourse/plugins/cloudrail-cap/discourse/components/cap-widget";

/**
 * Injects the Cap checkbox above the login form.
 *
 * Outlet: `login-before-modal-body`, declared by core in
 * frontend/discourse/app/templates/login.gjs.
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
    // See the signup connector: gate on the raw admin switch, not on `enabled`,
    // so a half-configured site is not silently blank.
    return Boolean(
      this.config?.plugin_enabled && this.config?.protect_login !== false
    );
  }

  <template>
    {{#if this.shouldShow}}
      <CapWidget
        @config={{this.config}}
        @context="login"
        @showStatus={{false}}
      />
    {{/if}}
  </template>
}
