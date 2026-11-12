# Values that make this environment different from the others.
# Every layer of the environment reads this file.

environment    = "prod"
aws_region     = "eu-west-1"
aws_account_id = "333333333333"

# Network. See docs/architecture/environments.md for the address plan.

vpc_cidr           = "10.30.0.0/16"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

# Access. The GitHub environment whose jobs may deploy here, and where this
# environment keeps its state.

github_environment = "production"
state_key_prefix   = "production"

# This environment holds data that matters. Protections against deletion stay
# on, and the pipeline cannot delete encryption keys. False is the default.
# It is stated so that the decision is visible in this file.
disposable = false

# Data stores. Production keeps two cache replicas, one in each other zone.

cache_replicas = 2
