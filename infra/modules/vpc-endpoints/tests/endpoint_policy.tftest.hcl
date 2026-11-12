# Plan-only tests of the endpoint policies. The provider is real with
# placeholder credentials so the rendered JSON can be read. Nothing is
# called: no AWS account or emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  name            = "meridian-prod-network"
  vpc_id          = "vpc-0123456789abcdef0"
  account_id      = "333333333333"
  vpc_cidr_block  = "10.30.0.0/16"
  route_table_ids = ["rtb-private-a"]
  subnet_ids      = ["subnet-private-a"]
  tags = {
    Project = "meridian"
  }
}

run "a_gateway_endpoint_reaches_only_this_accounts_resources" {
  command = plan

  assert {
    condition = alltrue([
      for service in ["s3", "dynamodb"] :
      jsondecode(data.aws_iam_policy_document.gateway[service].json).Statement[0].Condition.StringEquals["aws:ResourceAccount"] == "333333333333"
    ])
    error_message = "A gateway endpoint must not reach a bucket or table in another account."
  }
}

run "every_statement_admits_only_this_accounts_principals" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for document in concat([for policy in data.aws_iam_policy_document.gateway : policy.json], [data.aws_iam_policy_document.interface.json]) : [
        for statement in jsondecode(document).Statement :
        statement.Condition.StringEquals["aws:PrincipalAccount"] == "333333333333"
      ]
    ]))
    error_message = "Every endpoint policy statement must be limited to this account's principals."
  }
}

run "image_layers_can_still_be_pulled_through_the_s3_endpoint" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.gateway["s3"].json).Statement : statement
      if statement.Sid == "ReadContainerImageLayers"
    ]).Resource == "arn:aws:s3:::prod-eu-west-1-starport-layer-bucket/*"
    error_message = "The S3 endpoint must allow reading image layers from the bucket ECR owns in this region."
  }

  assert {
    condition = one([
      for statement in jsondecode(data.aws_iam_policy_document.gateway["s3"].json).Statement : statement
      if statement.Sid == "ReadContainerImageLayers"
    ]).Action == "s3:GetObject"
    error_message = "The exception for image layers is read-only."
  }
}

run "the_dynamodb_endpoint_has_no_exception" {
  command = plan

  assert {
    condition     = length(jsondecode(data.aws_iam_policy_document.gateway["dynamodb"].json).Statement) == 1
    error_message = "Only S3 needs an exception, for image layers."
  }
}
