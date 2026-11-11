# Bootstrap: the one stack that cannot store its state remotely, because it
# creates the place remote state is stored.
#
# It is applied once per organisation, by hand, with local state. See
# docs/runbooks/terraform-state.md for how its own state is then kept safe.

module "context" {
  source = "../modules/context"

  project     = var.project
  environment = var.environment
  component   = "tfstate"
}

module "state_bucket" {
  source = "../modules/state-bucket"

  # Bucket names are global, so the account and region make it unique.
  name = "${module.context.prefix}-${var.aws_account_id}-${var.aws_region}"
  tags = module.context.tags
}
