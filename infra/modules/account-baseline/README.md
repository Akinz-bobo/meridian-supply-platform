# account-baseline

Account-wide settings that make the safe choice the default for anything created in the account, including resources created outside Terraform.

| Setting | Effect |
| --- | --- |
| S3 account public access block | No bucket in the account can be made public |
| EBS encryption by default, with a customer managed key | Every new volume and snapshot is encrypted |
| IAM Access Analyzer | Reports resource policies that share a resource outside the account |
| IAM password policy | 14 characters or more, all character classes, no reuse of the last 24 |

What a caller needs to know:

- **None of these can be turned off through an input.** The module exists to guarantee them.
- **Call it once per account and region.** Every setting is a singleton: a second call would fight the first.
- **They are backstops.** Modules still encrypt and block public access themselves. These catch whatever a module or a person forgets.

See the [access model](../../../docs/architecture/access-model.md#account-baseline).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "account"
}

module "account_baseline" {
  source = "../.."

  name            = module.context.prefix
  tags            = module.context.tags
  ebs_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/11111111-2222-3333-4444-555555555555"
}
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| ebs\_kms\_key\_arn | Key that encrypts new EBS volumes by default. Pass the data key. | `string` | n/a | yes |
| name | Name of the access analyzer. Take it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for the resources that support them. Take them from the context module. | `map(string)` | n/a | yes |
| minimum\_password\_length | Shortest password an IAM user may set. | `number` | `14` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| access\_analyzer\_arn | ARN of the access analyzer. Its findings list resources shared outside the account. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_accessanalyzer_analyzer.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_ebs_default_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_default_kms_key) | resource |
| [aws_ebs_encryption_by_default.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default) | resource |
| [aws_iam_account_password_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_account_password_policy) | resource |
| [aws_s3_account_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_account_public_access_block) | resource |
<!-- END_TF_DOCS -->
