# Plan-only tests of the read policy. The provider is real with placeholder
# credentials so the rendered JSON can be read. No secret is generated in
# these tests, so nothing is called: no AWS account or emulator is needed.

provider "aws" {
  region                      = "eu-west-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

variables {
  path          = "/meridian/prod/catalog"
  account_id    = "333333333333"
  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  kms_key_alias = "alias/meridian-prod-secrets"
  tags = {
    Project = "meridian"
  }

  parameters = {
    log-level = "info"
  }

  secrets = {
    partner-api-token = {
      description = "Token for the partner's price feed."
    }
  }
}

run "a_service_can_read_only_its_own_path" {
  command = plan

  # Every resource in the policy is under this service's path, apart from
  # the key statement, which is narrowed by its conditions instead.
  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for resource in flatten([statement.Resource]) : strcontains(resource, "/meridian/prod/catalog/")
      ]
      if statement.Sid != "DecryptOwnSecrets"
    ]))
    error_message = "The read policy names a resource outside the service's own path."
  }

  assert {
    condition = one([
      for statement in jsondecode(output.read_policy_json).Statement : statement
      if statement.Sid == "ReadOwnParameters"
    ]).Resource == "arn:aws:ssm:eu-west-1:333333333333:parameter/meridian/prod/catalog/*"
    error_message = "Parameters are readable under the service's path only."
  }

  assert {
    condition = one([
      for statement in jsondecode(output.read_policy_json).Statement : statement
      if statement.Sid == "ReadOwnSecrets"
    ]).Resource == "arn:aws:secretsmanager:eu-west-1:333333333333:secret:/meridian/prod/catalog/secrets/*"
    error_message = "Secrets are readable under the service's path only."
  }
}

run "the_path_cannot_match_a_service_with_a_longer_name" {
  command = plan

  # /meridian/prod/catalog/* must not match /meridian/prod/catalog-import/...
  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for resource in flatten([statement.Resource]) : !endswith(resource, "/meridian/prod/catalog*")
      ]
    ]))
    error_message = "A resource pattern ends in the service name followed by *, which also matches other services whose names start the same way."
  }
}

run "the_key_can_be_used_only_for_the_services_own_secrets" {
  command = plan

  assert {
    condition = one([
      for statement in jsondecode(output.read_policy_json).Statement : statement
      if statement.Sid == "DecryptOwnSecrets"
    ]).Condition.StringLike["kms:EncryptionContext:SecretARN"] == "arn:aws:secretsmanager:eu-west-1:333333333333:secret:/meridian/prod/catalog/secrets/*"
    error_message = "Decryption must be tied to secrets under the service's path through the encryption context."
  }

  assert {
    condition = one([
      for statement in jsondecode(output.read_policy_json).Statement : statement
      if statement.Sid == "DecryptOwnSecrets"
    ]).Condition.StringEquals["kms:ViaService"] == "secretsmanager.eu-west-1.amazonaws.com"
    error_message = "The key may be used only through Secrets Manager."
  }
}

run "grants_no_write_or_delete_action" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for statement in jsondecode(output.read_policy_json).Statement : [
        for action in flatten([statement.Action]) : !can(regex(":(Put|Create|Delete|Update|Rotate|Tag)", action)) && !strcontains(action, "*")
      ]
    ]))
    error_message = "The read policy must contain read actions only, listed exactly."
  }
}

run "a_service_without_secrets_gets_no_secret_or_key_access" {
  command = plan

  variables {
    secrets = {}
  }

  assert {
    condition     = [for statement in jsondecode(output.read_policy_json).Statement : statement.Sid] == ["ReadOwnParameters"]
    error_message = "With no secrets, the policy must grant parameter access only."
  }
}
