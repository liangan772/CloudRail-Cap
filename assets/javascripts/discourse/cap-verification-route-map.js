// Registers the plugin's admin page with the Ember router.
//
// This file is REQUIRED. `add_admin_route` only tells the server to advertise a
// link on /admin/plugins; it does not create a frontend route. The route itself
// has to be declared here, otherwise `router.urlFor("adminPlugins.capverification")`
// throws and the plugin list renders:
//
//   Unable to configure link to '...'. Ensure ad-blockers are disabled and try
//   reloading the page.
//
// (That message is core's admin.plugins.broken_route, shown when
// adminRouteValid() in discourse/lib/admin-utilities.js cannot resolve the
// route — see frontend/discourse/admin/controllers/admin-plugins.js.)
//
// Any file matching `*-route-map.js` under assets/javascripts/discourse/ is
// picked up by the build automatically; it does not need registering in
// plugin.rb.
//
// The route name here must match the second argument of `add_admin_route` in
// plugin.rb ("capverification"), which is also the slug used for:
//   routes/admin-plugins-capverification.js
//   controllers/admin-plugins-capverification.js
//   templates/admin/plugins-capverification.gjs
//
// `resource: "admin.adminPlugins"` + `path: "/plugins"` places the route at
// /admin/plugins/capverification, matching the server-side scope in plugin.rb.
// This mirrors discourse-data-explorer's explorer-route-map.js.
export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("capverification");
  },
};
