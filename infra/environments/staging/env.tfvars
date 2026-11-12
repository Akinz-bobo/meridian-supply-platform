# Values that make this environment different from the others.
# Every layer of the environment reads this file.

environment    = "stg"
aws_region     = "eu-west-1"
aws_account_id = "222222222222"

# Network. See docs/architecture/environments.md for the address plan.

vpc_cidr           = "10.20.0.0/16"
availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

# Access. The GitHub environment whose jobs may deploy here, and where this
# environment keeps its state.

github_environment = "staging"
state_key_prefix   = "staging"

# Data stores. Staging has the structure of production at a smaller size.

database_instance_class        = "db.t4g.small"
database_backup_retention_days = 7
