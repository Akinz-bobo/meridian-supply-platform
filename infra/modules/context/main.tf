# Naming and tagging in one place.
#
# Every other module takes its names and tags from here, so the standard in
# docs/architecture/environments.md is enforced by construction and never
# re-implemented by string concatenation in a resource.

locals {
  prefix = "${var.project}-${var.environment}-${var.component}"

  standard_tags = {
    Project     = var.project
    Environment = var.environment
    Component   = var.component
    Owner       = var.owner
    CostCentre  = var.cost_centre
    ManagedBy   = "terraform"
    Repository  = var.repository
  }

  # Standard tags are merged last so that a caller cannot override them.
  tags = merge(var.extra_tags, local.standard_tags)
}
