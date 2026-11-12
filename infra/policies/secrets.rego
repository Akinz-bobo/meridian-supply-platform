# POL-SECRET: secret values stay out of Terraform, and secrets can be
# recovered after a mistaken delete.
#
# The convention is in docs/architecture/secrets-and-configuration.md.
package terraform.secrets

import rego.v1

import data.lib.plan

set(value) if {
	is_string(value)
	value != ""
}

# A value given through the ordinary argument is written to state and to
# the plan file. Write-only arguments (secret_string_wo, value_wo) are not.
deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_secretsmanager_secret_version"
	some attribute in ["secret_string", "secret_binary"]
	stored(rc, attribute)
	msg := sprintf(
		"POL-SECRET-1: %s sets %s, which stores the value in state. Use secret_string_wo, or set the value outside Terraform",
		[rc.address, attribute],
	)
}

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_ssm_parameter"
	rc.change.after.type == "SecureString"
	stored(rc, "value")
	msg := sprintf(
		"POL-SECRET-2: %s is a SecureString whose value would be stored in state. Use value_wo, or keep the secret in Secrets Manager",
		[rc.address],
	)
}

# An attribute is stored when it has a value now or will have one at apply.
stored(rc, attribute) if set(rc.change.after[attribute])

stored(rc, attribute) if plan.unknown(rc, attribute)

deny contains msg if {
	some rc in plan.changing
	rc.type == "aws_secretsmanager_secret"
	days := rc.change.after.recovery_window_in_days
	is_number(days)
	days < 7
	msg := sprintf(
		"POL-SECRET-3: %s can be deleted with a recovery window of %d days. The minimum is 7",
		[rc.address, days],
	)
}
