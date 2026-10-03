import { withPluginApi } from "discourse/lib/plugin-api";

// Must match the plugin's `# name:` (and therefore its directory name), which
// is what Admin::PluginsController#show looks up. Both are lowercase: an
// uppercase directory breaks core's stylesheet route (see plugin.rb).
const PLUGIN_ID = "cloudrail-cap";

/**
 * Adds this plugin's own page as a tab on /admin/plugins/cloudrail-cap.
 *
 * The shell there is rendered by core (route `adminPlugins.show`), which
 * builds its tab bar from whatever plugins register here. Core always appends
 * its own "Settings" tab pointing at the auto-generated site settings page, so
 * we only register the extra page.
 *
 * The registered `route` must exist, i.e. the route map must declare
 * `cap-verification` under `admin.adminPlugins.show`. An unknown route name
 * leaves a dead tab.
 */
export default {
  name: "cap-verification-admin-plugin-configuration-nav",

  initialize(container) {
    const currentUser = container.lookup("service:current-user");

    // Admin-only, and only worth doing for admins.
    if (!currentUser?.admin) {
      return;
    }

    withPluginApi((api) => {
      api.setAdminPluginIcon(PLUGIN_ID, "shield-halved");

      api.addAdminPluginConfigurationNav(PLUGIN_ID, [
        {
          label: "cap_verification.admin.tab_label",
          route: "adminPlugins.show.cap-verification",
          description: "cap_verification.admin.tab_description",
        },
      ]);
    });
  },
};
