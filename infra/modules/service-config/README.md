# service-config

A service's plain configuration and its secrets, under one path that belongs to it, with the IAM policy that lets the service read exactly that path.

```
<path>/config/<key>      Parameter Store
<path>/secrets/<name>    Secrets Manager
```

What a caller needs to know:

- **Secret values never enter Terraform state.** A secret with `generate` gets a random value from an ephemeral resource, written through a write-only argument. Terraform stores only a version number, and raising `version` generates a new value. A secret without `generate` is created empty for its owner to fill.
- **`read_policy_json` is the service's whole read access.** Attach it to the service's workload role. It names the service's path with a trailing slash, lists read actions only, and ties use of the key to secrets under that path through the encryption context.
- **Parameters are for values that are not sensitive.** They are stored unencrypted and appear in state. A parameter whose name looks like a secret is refused.
- **Secrets use the key passed in `kms_key_arn`** and can be recovered for 30 days after deletion by default, never fewer than 7.
- **Rotation is opt-in per secret**, with a Lambda function, at most 90 days apart.
- **Needs Terraform 1.11 or later**, for ephemeral resources and write-only arguments.

The module has plan tests in `tests/` and apply tests in `tests-emulator/`, which create, re-generate and destroy real secrets in the emulator.

The convention is described in [secrets and configuration](../../../docs/architecture/secrets-and-configuration.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "service_config" {
  source = "../.."

  path       = module.context.ssm_path
  tags       = module.context.tags
  account_id = "333333333333"

  kms_key_arn   = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
  kms_key_alias = "alias/meridian-prod-secrets"

  parameters = {
    log-level          = "info"
    supplier-file-size = "50"
  }

  secrets = {
    # Created with a random value that never enters Terraform state.
    webhook-signing-key = {
      description = "Signs webhooks sent to suppliers."
      generate    = {}
    }
    # Created empty. The value is issued by the partner and stored by hand.
    partner-api-token = {
      description = "Token for the partner's price feed."
    }
  }
}

# The policy is attached to the service's own role.
output "read_policy_json" {
  description = "Policy for the catalog service's role."
  value       = module.service_config.read_policy_json
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Account the configuration is stored in. Used to name resources exactly in the read policy. | `string` | n/a | yes |
| kms\_key\_alias | Alias of the same key, including the alias/ prefix. The read policy grants decryption by alias, which is known at plan time. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts the secrets. Pass the secrets key. | `string` | n/a | yes |
| path | Path the service owns, for example /meridian/prod/catalog. Take it from the context module's ssm\_path. | `string` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| parameters | Plain configuration values, keyed by name. Stored at <path>/config/<key>. Never put a secret here: these values are stored unencrypted and appear in Terraform state. | `map(string)` | `{}` | no |
| recovery\_window\_in\_days | Days a deleted secret can still be restored. | `number` | `30` | no |
| secrets | Secrets the service owns, keyed by name. Stored at <path>/secrets/<name>.<br/><br/>generate: create a random value. Without it the secret is created empty and its value is set outside Terraform.<br/>  version: raise it to generate and store a new value.<br/>rotation: rotate automatically with the given Lambda function. | <pre>map(object({<br/>    description = string<br/>    generate = optional(object({<br/>      length              = optional(number, 32)<br/>      exclude_punctuation = optional(bool, true)<br/>      version             = optional(number, 1)<br/>    }))<br/>    rotation = optional(object({<br/>      lambda_arn               = string<br/>      automatically_after_days = optional(number, 30)<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| parameter\_names | Full names of the parameters, keyed by the short name. |
| parameter\_path | Path to read all plain configuration from with one GetParametersByPath call. |
| read\_policy\_json | IAM policy that lets a role read this service's parameters and secrets, and nothing else. Attach it to the service's workload role. |
| secret\_arns | ARNs of the secrets, keyed by name. Reference these from a task definition or function, never the value. |
| secret\_names | Full names of the secrets, keyed by the short name. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_secretsmanager_secret.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_rotation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation) | resource |
| [aws_secretsmanager_secret_version.generated](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_ssm_parameter.config](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_iam_policy_document.read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
