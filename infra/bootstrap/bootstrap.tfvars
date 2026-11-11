# The shared-services account, which holds Terraform state for every
# environment. See docs/adr/0007-environments-and-account-isolation.md.

environment    = "shared"
aws_region     = "eu-west-1"
aws_account_id = "444444444444"
