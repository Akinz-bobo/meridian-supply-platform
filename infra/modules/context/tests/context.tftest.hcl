# The module is pure: no provider, no resources. These tests pin the naming
# and tagging standard so that it cannot change by accident.

variables {
  environment = "prod"
  component   = "inventory"
}

run "builds_the_prefix_from_project_environment_and_component" {
  command = plan

  assert {
    condition     = output.prefix == "meridian-prod-inventory"
    error_message = "Expected the prefix meridian-prod-inventory, got ${output.prefix}."
  }

  assert {
    condition     = output.ssm_path == "/meridian/prod/inventory"
    error_message = "Expected the path /meridian/prod/inventory, got ${output.ssm_path}."
  }
}

run "applies_every_standard_tag" {
  command = plan

  assert {
    condition = alltrue([
      for key in ["Project", "Environment", "Component", "Owner", "CostCentre", "ManagedBy", "Repository"] :
      contains(keys(output.tags), key)
    ])
    error_message = "A standard tag is missing."
  }

  assert {
    condition     = output.tags["ManagedBy"] == "terraform"
    error_message = "ManagedBy must always be terraform."
  }
}

run "keeps_extra_tags_but_never_lets_them_override_a_standard_tag" {
  command = plan

  variables {
    extra_tags = {
      DataClassification = "confidential"
      Environment        = "dev"
      ManagedBy          = "hand"
    }
  }

  assert {
    condition     = output.tags["DataClassification"] == "confidential"
    error_message = "An extra tag was dropped."
  }

  assert {
    condition     = output.tags["Environment"] == "prod" && output.tags["ManagedBy"] == "terraform"
    error_message = "An extra tag overrode a standard tag."
  }
}

run "rejects_an_unknown_environment" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.environment]
}

run "rejects_a_component_that_is_not_kebab_case" {
  command = plan

  variables {
    component = "Inventory_Service"
  }

  expect_failures = [var.component]
}

run "rejects_an_overlong_component" {
  command = plan

  variables {
    component = "a-component-name-that-is-far-too-long"
  }

  expect_failures = [var.component]
}
