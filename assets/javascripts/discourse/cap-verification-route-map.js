// Registers the plugin's own admin page with the Ember router.
//
// Any file matching `*-route-map.js` under assets/javascripts/discourse/ is
// picked up by the build automatically; it does not need registering in
// plugin.rb. The route map is applied by
// `frontend/discourse/app/mapping-router.js`, which looks up `resource` in the
// route tree and SILENTLY DROPS the map when the lookup fails - a wrong
// `resource` produces no error, just a route that never exists.
//
// `resource` must be "admin.adminPlugins.show" and NOT "admin.adminPlugins":
// core's admin route map only declares `adminPlugins` -> `show` -> `settings`,
// and the modern plugin show page mounts plugin routes under `show`. The
// sibling files in the Discourse repo all follow this:
//   plugins/discourse-ai/assets/javascripts/discourse/admin-discourse-ai-plugin-route-map.js
//   plugins/discourse-chat-integration/assets/javascripts/discourse/admin-chat-integration-plugin-route-map.js
//   plugins/discourse-data-explorer/assets/javascripts/discourse/explorer-route-map.js
// (data-explorer's explorer-legacy-route-map.js is the old "admin.adminPlugins"
// form, kept only for backwards compatibility.)
//
// `path: "/plugins"` matches the plugin show URL, so this route resolves to
//   /admin/plugins/<plugin_id>/verification
// with plugin_id being "cloudrail-cap" (see add_admin_route in plugin.rb).
//
// The route name `cap-verification` becomes `adminPlugins.show.cap-verification`
// and must match:
//   - the nav entry in
//     assets/javascripts/discourse/initializers/cap-verification-admin-plugin-configuration-nav.js
//   - admin/assets/javascripts/discourse/routes/admin-plugins/show/cap-verification.js
//   - admin/assets/javascripts/discourse/templates/admin-plugins/show/cap-verification.gjs
//
// Note: the path must not be "settings" - core already claims
// adminPlugins.show.settings for the auto-generated settings page.
export default {
  resource: "admin.adminPlugins.show",
  path: "/plugins",
  map() {
    this.route("cap-verification", { path: "verification" });
  },
};
