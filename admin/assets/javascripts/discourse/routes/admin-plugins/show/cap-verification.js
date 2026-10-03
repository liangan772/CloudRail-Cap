import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for the plugin's page at
 * /admin/plugins/cloudrail-cap/verification.
 *
 * Lives under `admin/assets/javascripts/...` rather than
 * `assets/javascripts/...`, which is where the modern plugin admin routes go.
 * The path mirrors the route name: `adminPlugins.show.cap-verification`
 *   -> routes/admin-plugins/show/cap-verification.js
 *
 * The JSON endpoint is deliberately outside /admin/plugins/<id> so it cannot
 * collide with core's own /admin/plugins/:plugin_id route.
 */
export default class CapVerificationRoute extends DiscourseRoute {
  model() {
    return ajax("/cap-verification/settings");
  }
}
