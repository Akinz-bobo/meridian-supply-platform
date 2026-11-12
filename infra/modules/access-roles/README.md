# access-roles

The roles through which the pipeline and people enter an environment: `deploy`, `operator` and `audit`, and the GitHub OpenID Connect provider the deploy role trusts.

What a caller needs to know:

- **The pipeline has no stored credentials.** GitHub Actions exchanges a signed token for the deploy role. `deploy_subjects` names exactly which repository and GitHub environment or branch may do so. A wildcard is refused, because it would admit pull requests from forks.
- **The deploy role cannot escalate.** It can create a role only if the role carries the workload boundary, cannot remove a boundary, and cannot change the boundary, itself, the other access roles or the identity provider.
- **The deploy role cannot destroy encryption keys** unless `allow_key_deletion` is set, which is meant for a disposable environment that the pipeline tears down.
- **The deploy role reaches only its own state.** Access to the state bucket is limited to `state_key_prefix`.
- **People need multi-factor authentication less than an hour old**, and come from `identity_account_id` only.
- **Operators operate and do not build.** They can restart, stop, redrive, snapshot and read logs, on resources named for the environment.
- **Auditors read configuration and never data.** The role has `SecurityAudit` and `ViewOnlyAccess`, and not `ReadOnlyAccess`.
- **One provider per account.** AWS allows a single OpenID Connect provider per URL in an account, so this module is called once per account.

See the [access model](../../../docs/architecture/access-model.md) and [decision record 0011](../../../docs/adr/0011-roles-not-users-and-a-boundary-on-every-workload.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "access"
}

module "access_roles" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  account_id          = "333333333333"
  region              = "eu-west-1"
  identity_account_id = "444444444444"
  deploy_subjects     = ["repo:example-org/example-repository:environment:production"]

  resource_prefix          = "meridian-prod-"
  path_prefix              = "/meridian/prod/"
  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"
  logs_key_alias           = "alias/meridian-prod-logs"

  state_bucket_name = "meridian-shared-tfstate-444444444444-eu-west-1"
  state_key_prefix  = "production"
  state_account_id  = "444444444444"
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
| account\_id | Account of the environment the roles give access to. | `string` | n/a | yes |
| deploy\_subjects | GitHub OpenID Connect subjects allowed to assume the deploy role, for example repo:owner/repository:environment:production. | `set(string)` | n/a | yes |
| identity\_account\_id | Account where people sign in. Its principals may assume the operator and audit roles, with multi-factor authentication. | `string` | n/a | yes |
| logs\_key\_alias | Alias of the key that encrypts log groups, including the alias/ prefix. Operators may decrypt with it, and with no other key. | `string` | n/a | yes |
| name | Prefix of the roles: <name>-deploy, <name>-operator and <name>-audit. Take it from the context module's prefix. | `string` | n/a | yes |
| path\_prefix | Path that every log group of the environment lives under, including the trailing slash, for example /meridian/prod/. | `string` | n/a | yes |
| permissions\_boundary\_arn | ARN of the workload permission boundary. The pipeline can create a role only if the role carries it. | `string` | n/a | yes |
| region | Region the environment is deployed to. The pipeline can manage resources in this region only. | `string` | n/a | yes |
| resource\_prefix | Prefix that every named resource of the environment starts with, including the trailing hyphen, for example meridian-prod-. | `string` | n/a | yes |
| state\_account\_id | Account that owns the state bucket and its key. | `string` | n/a | yes |
| state\_bucket\_name | Name of the bucket that holds Terraform state. | `string` | n/a | yes |
| state\_key\_prefix | Prefix of this environment's state in the bucket, without slashes, for example production. The pipeline can read and write only under it. | `string` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| allow\_key\_deletion | Let the pipeline disable encryption keys and schedule them for deletion. Only for an environment whose data is disposable and which the pipeline tears down. | `bool` | `false` | no |
| deploy\_services | AWS services the pipeline manages, by IAM prefix. IAM is handled separately and may not be listed. | `set(string)` | <pre>[<br/>  "apigateway",<br/>  "athena",<br/>  "cloudfront",<br/>  "cloudwatch",<br/>  "dynamodb",<br/>  "ec2",<br/>  "ecr",<br/>  "ecs",<br/>  "eks",<br/>  "elasticache",<br/>  "elasticloadbalancing",<br/>  "events",<br/>  "firehose",<br/>  "glue",<br/>  "kinesis",<br/>  "kms",<br/>  "lambda",<br/>  "logs",<br/>  "rds",<br/>  "s3",<br/>  "scheduler",<br/>  "secretsmanager",<br/>  "sns",<br/>  "sqs",<br/>  "ssm",<br/>  "states"<br/>]</pre> | no |
| service\_boundary\_arns | Further boundaries the pipeline may create roles with, for AWS service roles whose work falls outside the workload boundary. Each must be an AWS managed policy written for one service, such as the backup service's own policy. | `set(string)` | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| audit\_role\_arn | ARN of the role security reviewers assume. |
| deploy\_role\_arn | ARN of the role GitHub Actions assumes. Set it as role-to-assume in the workflow. |
| github\_oidc\_provider\_arn | ARN of the GitHub OpenID Connect provider in this account. |
| operator\_role\_arn | ARN of the role on-call engineers assume. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_policy.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.audit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.audit](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.deploy_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.operator](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.people_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
