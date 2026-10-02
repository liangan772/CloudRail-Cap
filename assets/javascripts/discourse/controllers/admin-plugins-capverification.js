import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * Controller for the Cap verification admin screen.
 *
 * Discourse splits an admin plugin page across three files:
 *   routes/admin-plugins-<slug>.js       -> loads the model
 *   controllers/admin-plugins-<slug>.js  -> state + actions   (this file)
 *   templates/admin/plugins-<slug>.gjs   -> renders, via @model/@controller
 *
 * The route spreads the JSON payload onto this controller with
 * `controller.setProperties(model)`, so `enabled`, `instance_url`,
 * `protect_signup` etc. arrive as plain properties here.
 *
 * IMPORTANT: the controller is instantiated before the payload arrives, so no
 * property initialisation may depend on it. Anything derived is a getter; the
 * editable copy is created lazily by `fields`.
 */
export default class AdminPluginsCapverificationController extends Controller {
  @service router;

  @tracked saving = false;
  @tracked testing = false;
  @tracked notice = null;
  @tracked noticeClass = "is-info";

  /** Local, user-editable copy of the settings. Null until first read. */
  @tracked _fields = null;

  themes = ["light", "dark", "auto"];

  /**
   * Editable form state, seeded from the server payload on first access and
   * replaced after a save. Kept separate from the spread properties so that
   * typing does not mutate the loaded record.
   */
  get fields() {
    if (!this._fields) {
      this._fields = this.#buildFields();
    }
    return this._fields;
  }

  get statusLabel() {
    const prefix = "cap_verification.admin.";
    if (!this.enabled) {
      return i18n(`${prefix}status_disabled`);
    }
    if (!this.running) {
      return i18n(`${prefix}status_incomplete`);
    }
    return i18n(`${prefix}status_running`);
  }

  get statusClass() {
    if (!this.enabled) {
      return "is-disabled";
    }
    return this.running ? "is-running" : "is-incomplete";
  }

  /** Secret is never echoed back by the server, so it always starts blank. */
  #buildFields() {
    return {
      instance_url: this.instance_url || "",
      site_key: this.site_key || "",
      secret_key: "",
      widget_theme: this.widget_theme || "light",
      widget_script_url: this.widget_script_url || "",
      protect_signup: Boolean(this.protect_signup),
      protect_login: Boolean(this.protect_login),
      skip_for_staff: Boolean(this.skip_for_staff),
      min_trust_level: this.min_trust_level ?? 0,
      max_attempts: this.max_attempts ?? 10,
      timeout_seconds: this.timeout_seconds ?? 5,
    };
  }

  @action
  setField(name, event) {
    this._fields = { ...this.fields, [name]: event.target.value };
  }

  @action
  toggleField(name, event) {
    this._fields = { ...this.fields, [name]: event.target.checked };
  }

  @action
  async save(event) {
    event.preventDefault();
    this.saving = true;
    this.notice = null;

    try {
      const payload = { ...this.fields };

      // Never overwrite the stored secret with an empty string: an untouched
      // password field means "keep what is already saved".
      if (!payload.secret_key) {
        delete payload.secret_key;
      }

      const updated = await ajax("/admin/plugins/capverification", {
        type: "PUT",
        data: { cap_verification: payload },
      });

      this.setProperties(updated);
      this._fields = null;
      this.#showNotice(i18n("cap_verification.admin.saved"), "is-success");
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async testConnection() {
    this.testing = true;
    this.notice = null;

    try {
      const result = await ajax("/admin/plugins/capverification/test", {
        type: "POST",
      });

      if (result.success) {
        this.#showNotice(
          result.message || i18n("cap_verification.admin.connection_ok"),
          "is-success"
        );
      } else {
        this.#showNotice(
          result.error || i18n("cap_verification.admin.connection_failed"),
          "is-error"
        );
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.testing = false;
    }
  }

  #showNotice(message, cssClass) {
    this.notice = message;
    this.noticeClass = cssClass;
  }
}
