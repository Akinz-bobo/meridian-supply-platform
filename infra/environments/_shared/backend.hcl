# Where every environment keeps its state. The key is added per layer:
#   <environment>/<layer>/terraform.tfstate

bucket       = "meridian-shared-tfstate-444444444444-eu-west-1"
region       = "eu-west-1"
encrypt      = true
kms_key_id   = "alias/meridian-shared-tfstate-444444444444-eu-west-1"
use_lockfile = true
