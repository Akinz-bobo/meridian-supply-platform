module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "inventory"
}

module "redis_cache" {
  source = "../.."

  name        = "${module.context.prefix}-cache"
  tags        = module.context.tags
  description = "Read cache of stock availability for the inventory service."
  account_id  = "333333333333"

  data_classification = "internal"

  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn      = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  logs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
  log_group_name   = "${module.context.ssm_path}/cache/slow-log"

  # The inventory service reads and writes keys under stock: and can run no
  # administrative or dangerous command.
  users = {
    inventory = {
      access_string = "on ~stock:* +@read +@write +@connection -@dangerous"
    }
  }
}

# Attached to the inventory service's role.
output "connect_policy_json" {
  description = "Policy that lets the inventory service connect as its cache user."
  value       = module.redis_cache.connect_policy_json["inventory"]
}
