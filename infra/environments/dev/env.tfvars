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

# Dev is rebuilt freely. This lets the pipeline delete encryption keys there,
# which staging and production do not allow.
disposable = true

# Data stores. Dev runs the smallest instance, in one zone, with a day of
# backups. See docs/architecture/data.md.

database_instance_class        = "db.t4g.micro"
database_multi_az              = false
database_backup_retention_days = 1
