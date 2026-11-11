package terraform.region_test

import rego.v1

import data.lib.fixtures
import data.terraform.region

approved := {"allowed_regions": ["eu-west-1"]}

test_allows_an_approved_region if {
	count(region.deny) == 0 with input as fixtures.plan("prod", []) with data.settings as approved
}

test_denies_a_region_that_is_not_approved if {
	elsewhere := object.union(fixtures.plan("prod", []), {"variables": {"aws_region": {"value": "us-east-1"}}})
	messages := region.deny with input as elsewhere with data.settings as approved
	some msg in messages
	contains(msg, "POL-REGION-1")
	contains(msg, "us-east-1")
}
