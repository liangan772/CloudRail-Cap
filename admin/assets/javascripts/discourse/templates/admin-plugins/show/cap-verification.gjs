import CapVerificationSettings from "../../../components/cap-verification-settings";

// A bare <template> in templates/ is the route template: it receives
// {{@model}} and {{@controller}}. Core's own frontend/discourse/admin/templates
// and the other plugins' admin pages use the same shape
// (see plugins/discourse-ai/.../templates/admin-plugins/show/discourse-ai-spam.gjs).
//
// The real UI lives in the component so it can hold state and actions without
// fighting the controller lifecycle - a controller is constructed before the
// model arrives, which is how the earlier "blank page" bug happened.
export default <template>
  <CapVerificationSettings @model={{@controller.model}} />
</template>;
