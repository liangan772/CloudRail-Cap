import { fn, eq } from "@ember/helper";
import { on } from "@ember/modifier";
import RouteTemplate from "ember-route-template";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

export default RouteTemplate(
  <template>
    <div class="cap-verification-admin">
      <div class="admin-page-header">
        <h1>{{i18n "cap_verification.admin.title"}}</h1>
        <p class="admin-page-header__description">
          {{i18n "cap_verification.admin.description"}}
        </p>
      </div>

      <div class="cap-status-row">
        <span class="cap-status-badge {{@controller.statusClass}}">
          {{@controller.statusLabel}}
        </span>
        {{#if @controller.failed_last_24h}}
          <span class="cap-status-meta">
            {{i18n
              "cap_verification.admin.failed_last_24h"
              count=@controller.failed_last_24h
            }}
          </span>
        {{/if}}
      </div>

      <form class="cap-form" {{on "submit" @controller.save}}>
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
                value={{@controller.fields.instance_url}}
                {{on "input" (fn @controller.setField "instance_url")}}
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
                value={{@controller.fields.site_key}}
                {{on "input" (fn @controller.setField "site_key")}}
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
                  @controller.secret_key_set
                  (i18n "cap_verification.admin.secret_key_placeholder")
                }}
                value={{@controller.fields.secret_key}}
                {{on "input" (fn @controller.setField "secret_key")}}
              />
              <p class="cap-hint">
                {{i18n "cap_verification.admin.secret_key_help"}}
              </p>
              {{#if @controller.secret_key_set}}
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
                {{on "change" (fn @controller.setField "widget_theme")}}
              >
                {{#each @controller.themes as |theme|}}
                  <option
                    value={{theme}}
                    selected={{eq theme @controller.fields.widget_theme}}
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
                value={{@controller.fields.widget_script_url}}
                {{on "input" (fn @controller.setField "widget_script_url")}}
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
                checked={{@controller.fields.protect_signup}}
                {{on "change" (fn @controller.toggleField "protect_signup")}}
              />
              <span>{{i18n "cap_verification.admin.protect_signup"}}</span>
            </label>
          </div>

          <div class="cap-row cap-row-inline">
            <label class="cap-checkbox">
              <input
                type="checkbox"
                checked={{@controller.fields.protect_login}}
                {{on "change" (fn @controller.toggleField "protect_login")}}
              />
              <span>{{i18n "cap_verification.admin.protect_login"}}</span>
            </label>
          </div>

          <div class="cap-row cap-row-inline">
            <label class="cap-checkbox">
              <input
                type="checkbox"
                checked={{@controller.fields.skip_for_staff}}
                {{on "change" (fn @controller.toggleField "skip_for_staff")}}
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
                value={{@controller.fields.min_trust_level}}
                {{on "input" (fn @controller.setField "min_trust_level")}}
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
                value={{@controller.fields.max_attempts}}
                {{on "input" (fn @controller.setField "max_attempts")}}
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
                value={{@controller.fields.timeout_seconds}}
                {{on "input" (fn @controller.setField "timeout_seconds")}}
              />
            </div>
          </div>
        </fieldset>

        <div class="cap-actions">
          <DButton
            @type="submit"
            @label="cap_verification.admin.save"
            @disabled={{@controller.saving}}
            class="btn-primary"
          />
          <DButton
            @action={{@controller.testConnection}}
            @label="cap_verification.admin.test"
            @disabled={{@controller.testing}}
          />
        </div>
      </form>

      {{#if @controller.notice}}
        <div class="cap-notice {{@controller.noticeClass}}">
          {{@controller.notice}}
        </div>
      {{/if}}

      <div class="cap-section cap-howto">
        <h3>{{i18n "cap_verification.admin.how_to_heading"}}</h3>
        <p>{{i18n "cap_verification.admin.how_to_body"}}</p>
      </div>
    </div>
  </template>
);
