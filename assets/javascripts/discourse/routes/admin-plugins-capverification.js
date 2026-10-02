import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

/**
 * Route for the Cap verification admin screen.
 *
 * `add_admin_route "cap_verification.admin.title", "capverification",
 * use_new_show_route: false` in plugin.rb creates the route name
 * `adminPlugins.capverification`, which resolves by convention to:
 *
 *   route      -> routes/admin-plugins-capverification.js        (this file)
 *   controller -> controllers/admin-plugins-capverification.js
 *   template   -> templates/admin/plugins-capverification.gjs
 *
 * The public path stays /admin/plugins/capverification.
 */
export default class AdminPluginsCapverificationRoute extends DiscourseRoute {
  model() {
    return ajax("/admin/plugins/capverification");
  }

  /**
   * The payload's keys are spread onto the controller rather than left on
   * `controller.model`. This is the convention used by core-official plugins
   * (see discourse-data-explorer's admin-plugins-explorer-index route), and it
   * keeps the template reading `{{@controller.foo}}` for both loaded data and
   * UI state.
   *
   * It also matters for correctness: the controller instance is constructed
   * before the model is known, so anything that needs the payload must be
   * derived here (or in a getter), never in the controller's constructor.
   */
  setupController(controller, model) {
    controller.setProperties(model);
  }
}
