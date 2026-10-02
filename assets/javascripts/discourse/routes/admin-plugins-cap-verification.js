import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

/**
 * Route for the plugin's admin settings screen.
 *
 * Registered by `add_admin_route "cap_verification.admin.title",
 * "cap-verification", use_new_show_route: true` in plugin.rb, which maps the
 * slug `cap-verification` onto this file.
 */
export default class CapVerificationAdminRoute extends Route {
  model() {
    return ajax("/admin/plugins/cap-verification");
  }
}
