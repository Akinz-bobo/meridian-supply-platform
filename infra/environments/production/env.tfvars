# Values that make this environment different from the others.
# Every layer of the environment reads this file.

environment    = "prod"
aws_region     = "eu-west-1"
aws_account_id = "333333333333"

# Network. See docs/architecture/environments.md for the address plan.

vpc_cidr           = "10.30.0.0/16"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
