<template>
  <div class="cap-verification-admin">
    <div class="admin-page-header">
      <h1>{{i18n "cap_verification.admin.title"}}</h1>
      <p class="admin-page-header__description">
        {{i18n "cap_verification.admin.description"}}
      </p>
    </div>

    <div class="cap-status-row">
      <span class="cap-status-badge {{this.statusClass}}">
        {{this.statusLabel}}
      </span>
      {{#if this.args.model.failed_last_24h}}
        <span class="cap-status-meta">
          {{i18n
            "cap_verification.admin.failed_last_24h"
            count=this.args.model.failed_last_24h
          }}
        </span>
      {{/if}}
    </div>

    <form class="cap-form" {{on "submit" this.save}}>
      <fieldset class="cap-section">
        <legend>{{i18n "cap_verification.admin.setup_heading"}}</legend>

        <div class="cap-row">
          <label for="cap-instance-url">
            {{i18n "cap_verification.admin.instance_url"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-instance-url"
              type="url"
              class="cap-input"
              placeholder="https://cap.example.com"
              value={{this.fields.instance_url}}
              {{on "input" (fn this.setField "instance_url")}}
            />
            <p class="cap-hint">
              {{i18n "cap_verification.admin.instance_url_help"}}
            </p>
          </div>
        </div>

        <div class="cap-row">
          <label for="cap-site-key">
            {{i18n "cap_verification.admin.site_key"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-site-key"
              type="text"
              class="cap-input"
              value={{this.fields.site_key}}
              {{on "input" (fn this.setField "site_key")}}
            />
            <p class="cap-hint">
              {{i18n "cap_verification.admin.site_key_help"}}
            </p>
          </div>
        </div>

        <div class="cap-row">
          <label for="cap-secret-key">
            {{i18n "cap_verification.admin.secret_key"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-secret-key"
              type="password"
              class="cap-input"
              autocomplete="new-password"
              placeholder={{if
                this.args.model.secret_key_set
                (i18n "cap_verification.admin.secret_key_placeholder")
              }}
              value={{this.fields.secret_key}}
              {{on "input" (fn this.setField "secret_key")}}
            />
            <p class="cap-hint">
              {{i18n "cap_verification.admin.secret_key_help"}}
            </p>
            {{#if this.args.model.secret_key_set}}
              <p class="cap-hint cap-hint-ok">
                {{i18n "cap_verification.admin.secret_key_set"}}
              </p>
            {{/if}}
          </div>
        </div>
      </fieldset>

      <fieldset class="cap-section">
        <legend>{{i18n "cap_verification.admin.widget_heading"}}</legend>

        <div class="cap-row">
          <label for="cap-widget-theme">
            {{i18n "cap_verification.admin.widget_theme"}}
          </label>
          <div class="cap-control">
            <select
              id="cap-widget-theme"
              class="cap-input"
              {{on "change" (fn this.setField "widget_theme")}}
            >
              {{#each this.themes as |theme|}}
                <option
                  value={{theme}}
                  selected={{eq theme this.fields.widget_theme}}
                >{{theme}}</option>
              {{/each}}
            </select>
            <p class="cap-hint">
              {{i18n "cap_verification.admin.widget_theme_help"}}
            </p>
          </div>
        </div>

        <div class="cap-row">
          <label for="cap-script-url">
            {{i18n "cap_verification.admin.widget_script_url"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-script-url"
              type="text"
              class="cap-input"
              value={{this.fields.widget_script_url}}
              {{on "input" (fn this.setField "widget_script_url")}}
            />
            <p class="cap-hint">
              {{i18n "cap_verification.admin.widget_script_url_help"}}
            </p>
          </div>
        </div>
      </fieldset>

      <fieldset class="cap-section">
        <legend>{{i18n "cap_verification.admin.protection_heading"}}</legend>

        <div class="cap-row cap-row-inline">
          <label class="cap-checkbox">
            <input
              type="checkbox"
              checked={{this.fields.protect_signup}}
              {{on "change" (fn this.toggleField "protect_signup")}}
            />
            <span>{{i18n "cap_verification.admin.protect_signup"}}</span>
          </label>
        </div>

        <div class="cap-row cap-row-inline">
          <label class="cap-checkbox">
            <input
              type="checkbox"
              checked={{this.fields.protect_login}}
              {{on "change" (fn this.toggleField "protect_login")}}
            />
            <span>{{i18n "cap_verification.admin.protect_login"}}</span>
          </label>
        </div>

        <div class="cap-row cap-row-inline">
          <label class="cap-checkbox">
            <input
              type="checkbox"
              checked={{this.fields.skip_for_staff}}
              {{on "change" (fn this.toggleField "skip_for_staff")}}
            />
            <span>{{i18n "cap_verification.admin.skip_for_staff"}}</span>
          </label>
        </div>

        <div class="cap-row">
          <label for="cap-min-tl">
            {{i18n "cap_verification.admin.min_trust_level"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-min-tl"
              type="number"
              min="0"
              max="4"
              class="cap-input cap-input-small"
              value={{this.fields.min_trust_level}}
              {{on "input" (fn this.setField "min_trust_level")}}
            />
            <p class="cap-hint">
              {{i18n "cap_verification.admin.min_trust_level_help"}}
            </p>
          </div>
        </div>
      </fieldset>

      <fieldset class="cap-section">
        <legend>{{i18n "cap_verification.admin.advanced_heading"}}</legend>

        <div class="cap-row">
          <label for="cap-max-attempts">
            {{i18n "cap_verification.admin.max_attempts"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-max-attempts"
              type="number"
              min="1"
              max="200"
              class="cap-input cap-input-small"
              value={{this.fields.max_attempts}}
              {{on "input" (fn this.setField "max_attempts")}}
            />
          </div>
        </div>

        <div class="cap-row">
          <label for="cap-timeout">
            {{i18n "cap_verification.admin.timeout_seconds"}}
          </label>
          <div class="cap-control">
            <input
              id="cap-timeout"
              type="number"
              min="1"
              max="60"
              class="cap-input cap-input-small"
              value={{this.fields.timeout_seconds}}
              {{on "input" (fn this.setField "timeout_seconds")}}
            />
          </div>
        </div>
      </fieldset>

      <div class="cap-actions">
        <DButton
          @type="submit"
          @label="cap_verification.admin.save"
          @disabled={{this.saving}}
          class="btn-primary"
        />
        <DButton
          @action={{this.testConnection}}
          @label="cap_verification.admin.test"
          @disabled={{this.testing}}
        />
      </div>
    </form>

    {{#if this.notice}}
      <div class="cap-notice {{this.noticeClass}}">{{this.notice}}</div>
    {{/if}}

    <div class="cap-section cap-howto">
      <h3>{{i18n "cap_verification.admin.how_to_heading"}}</h3>
      <p>{{i18n "cap_verification.admin.how_to_body"}}</p>
    </div>
  </div>
</template>

<script>
  import Component from "@glimmer/component";
  import { tracked } from "@glimmer/tracking";
  import { action } from "@ember/object";
  import { fn, eq } from "@ember/helper";
  import { on } from "@ember/modifier";
  import { service } from "@ember/service";
  import { ajax } from "discourse/lib/ajax";
  import { popupAjaxError } from "discourse/lib/ajax-error";
  import DButton from "discourse/components/d-button";
  import { i18n } from "discourse-i18n";

  /**
   * Admin settings screen for Cap verification.
   *
   * Written in the modern `.gjs` format. `.hbs` templates are deprecated and
   * support is scheduled for removal after the 2026.7 ESR, see
   * https://meta.discourse.org/t/deprecating-hbs-file-extension-in-themes-and-plugins/398896
   */
  export default class CapVerificationAdmin extends Component {
    @service router;

    @tracked saving = false;
    @tracked testing = false;
    @tracked notice = null;
    @tracked noticeClass = "is-info";
    @tracked fields = {};

    themes = ["light", "dark", "auto"];

    constructor() {
      super(...arguments);
      this.fields = this.buildFields(this.args.model);
    }

    buildFields(model) {
      return {
        instance_url: model.instance_url || "",
        site_key: model.site_key || "",
        secret_key: "",
        widget_theme: model.widget_theme || "light",
        widget_script_url: model.widget_script_url || "",
        protect_signup: model.protect_signup,
        protect_login: model.protect_login,
        skip_for_staff: model.skip_for_staff,
        min_trust_level: model.min_trust_level,
        max_attempts: model.max_attempts,
        timeout_seconds: model.timeout_seconds,
      };
    }

    get statusLabel() {
      const prefix = "cap_verification.admin.";
      if (!this.args.model.enabled) {
        return i18n(`${prefix}status_disabled`);
      }
      if (!this.args.model.running) {
        return i18n(`${prefix}status_incomplete`);
      }
      return i18n(`${prefix}status_running`);
    }

    get statusClass() {
      if (!this.args.model.enabled) {
        return "is-disabled";
      }
      return this.args.model.running ? "is-running" : "is-incomplete";
    }

    @action
    setField(name, event) {
      this.fields = { ...this.fields, [name]: event.target.value };
    }

    @action
    toggleField(name, event) {
      this.fields = { ...this.fields, [name]: event.target.checked };
    }

    @action
    async save(event) {
      event.preventDefault();
      this.saving = true;
      this.notice = null;

      try {
        const payload = { ...this.fields };
        // Never overwrite the stored secret with an empty string.
        if (!payload.secret_key) {
          delete payload.secret_key;
        }

        await ajax("/admin/plugins/cap-verification", {
          type: "PUT",
          data: { cap_verification: payload },
        });

        this.fields = { ...this.fields, secret_key: "" };
        this.showNotice(i18n("cap_verification.admin.saved"), "is-success");
        this.router.refresh();
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
        const result = await ajax("/admin/plugins/cap-verification/test", {
          type: "POST",
        });

        if (result.success) {
          this.showNotice(
            result.message || i18n("cap_verification.admin.connection_ok"),
            "is-success"
          );
        } else {
          this.showNotice(result.error, "is-error");
        }
      } catch (error) {
        popupAjaxError(error);
      } finally {
        this.testing = false;
      }
    }

    showNotice(message, cls) {
      this.notice = message;
      this.noticeClass = cls;
    }
  }
</script>
