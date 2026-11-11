module "context" {
  source = "../.."

  environment = "prod"
  component   = "inventory"

  extra_tags = {
    DataClassification = "confidential"
  }
}

# Take every name and tag from the module. Append a qualifier to the prefix
# to tell sibling resources apart.
output "queue_name" {
  description = "meridian-prod-inventory-movements"
  value       = "${module.context.prefix}-movements"
}

output "tags" {
  description = "The standard tags plus DataClassification."
  value       = module.context.tags
}
