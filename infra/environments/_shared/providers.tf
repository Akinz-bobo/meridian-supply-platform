# Shared by every layer of every environment through a symbolic link.
#
# One variable decides the target. With aws_endpoint_url unset, this is an
# ordinary AWS provider that takes credentials from the environment. With it
# set, every service is pointed at the emulator. Nothing else in the
# repository knows which one is in use.

locals {
  emulated = var.aws_endpoint_url != null
}

provider "aws" {
  region = var.aws_region

  # Refuse to run against any account other than the one this environment
  # is declared to live in.
  allowed_account_ids = [var.aws_account_id]

  # The emulator derives the account from the access key, which is how each
  # environment gets its own account locally. These are not credentials: on
  # real AWS both are null and the standard credential chain is used.
  access_key = local.emulated ? var.aws_account_id : null
  secret_key = local.emulated ? "emulator" : null

  skip_credentials_validation = local.emulated
  skip_metadata_api_check     = local.emulated
  s3_use_path_style           = local.emulated

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "Akinz-bobo/meridian-supply-platform"
    }
  }

  # A null value leaves the service on its real endpoint.
  endpoints {
    acm                    = var.aws_endpoint_url
    amp                    = var.aws_endpoint_url
    apigateway             = var.aws_endpoint_url
    apigatewayv2           = var.aws_endpoint_url
    applicationautoscaling = var.aws_endpoint_url
    athena                 = var.aws_endpoint_url
    autoscaling            = var.aws_endpoint_url
    backup                 = var.aws_endpoint_url
    budgets                = var.aws_endpoint_url
    cloudfront             = var.aws_endpoint_url
    cloudtrail             = var.aws_endpoint_url
    cloudwatch             = var.aws_endpoint_url
    cognitoidp             = var.aws_endpoint_url
    configservice          = var.aws_endpoint_url
    dynamodb               = var.aws_endpoint_url
    ec2                    = var.aws_endpoint_url
    ecr                    = var.aws_endpoint_url
    ecs                    = var.aws_endpoint_url
    eks                    = var.aws_endpoint_url
    elasticache            = var.aws_endpoint_url
    elbv2                  = var.aws_endpoint_url
    events                 = var.aws_endpoint_url
    firehose               = var.aws_endpoint_url
    glue                   = var.aws_endpoint_url
    iam                    = var.aws_endpoint_url
    kinesis                = var.aws_endpoint_url
    kms                    = var.aws_endpoint_url
    lambda                 = var.aws_endpoint_url
    logs                   = var.aws_endpoint_url
    rds                    = var.aws_endpoint_url
    route53                = var.aws_endpoint_url
    s3                     = var.aws_endpoint_url
    scheduler              = var.aws_endpoint_url
    secretsmanager         = var.aws_endpoint_url
    sesv2                  = var.aws_endpoint_url
    sfn                    = var.aws_endpoint_url
    sns                    = var.aws_endpoint_url
    sqs                    = var.aws_endpoint_url
    ssm                    = var.aws_endpoint_url
    sts                    = var.aws_endpoint_url
    wafv2                  = var.aws_endpoint_url
    xray                   = var.aws_endpoint_url
  }
}
