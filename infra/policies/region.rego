# POL-REGION: infrastructure is created only in approved regions.
#
# Where data is stored is a legal and contractual matter, not a technical
# preference. The approved list is in data/settings.yaml and changing it is
# a reviewed decision.
package terraform.region

import rego.v1

import data.lib.plan

deny contains msg if {
	not plan.region in data.settings.allowed_regions
	msg := sprintf(
		"POL-REGION-1: region %q is not approved. Approved regions: %s",
		[plan.region, concat(", ", data.settings.allowed_regions)],
	)
}
