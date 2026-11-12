# Values that make this environment different from the others.
# Every layer of the environment reads this file.

environment    = "dev"
aws_region     = "eu-west-1"
aws_account_id = "111111111111"

# Network. See docs/architecture/environments.md for the address plan.

vpc_cidr           = "10.10.0.0/16"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
single_nat_gateway = true

# Interface endpoints are billed per zone per hour. Dev keeps only the ones
# needed to pull images and read secrets, and uses NAT for the rest.
interface_endpoint_services = ["ecr.api", "ecr.dkr", "secretsmanager"]

log_retention_days = 30

# Access. The GitHub environment whose jobs may deploy here, and where this
# environment keeps its state.

github_environment = "dev"
state_key_prefix   = "dev"
