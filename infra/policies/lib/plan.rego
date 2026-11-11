# Helpers for reading a Terraform plan in JSON form
# (terraform show -json <planfile>).
package lib.plan

import rego.v1

# Every resource the plan would create or update, with its planned values.
changing contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

# Every resource the plan would delete, including replacements.
deleting contains rc if {
	some rc in input.resource_changes
	"delete" in rc.change.actions
}

environment := input.variables.environment.value

project := input.variables.project.value

region := input.variables.aws_region.value

# True when an attribute's value is not known until apply. Such values
# cannot be checked at plan time.
unknown(rc, attribute) if rc.change.after_unknown[attribute] == true

# Parses a JSON policy document held in a string attribute. Returns nothing
# when the attribute is missing, unknown or not valid JSON.
policy_document(rc, attribute) := document if {
	raw := rc.change.after[attribute]
	is_string(raw)
	document := json.unmarshal(raw)
}

# IAM allows a single value or a list almost everywhere. Normalise to a list.
as_list(value) := value if is_array(value)

as_list(value) := [value] if not is_array(value)

statements(document) := as_list(document.Statement)
