import { apiInitializer } from "discourse/lib/api";
import loadScript from "discourse/lib/load-script";

/**
 * Loads cap-widget once per page load, and only when the site has actually
 * enabled Cap. Loading the script lazily keeps it out of the critical path for
 * anonymous crawlers and for sites that have the plugin installed but disabled.
 *
 * The config lives on the `site` service, not `siteSettings` - the server
 * publishes it with `add_to_serializer(:site, :cap_verification)`.
 *
 * Cap docs: https://trycap.dev/zh/guide
 */
export default apiInitializer((api) => {
  const container = api.container;
  const site = container.lookup("service:site");
  const config = site.cap_verification;

  if (!config?.enabled || !config?.script_url) {
    return;
  }

  // `script_url` may point at the jsDelivr default or a self-hosted copy.
  loadScript(config.script_url).catch((error) => {
    // eslint-disable-next-line no-console
    console.error("[cap-verification] failed to load cap-widget", error);
  });
});
