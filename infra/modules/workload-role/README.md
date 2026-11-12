# workload-role

The IAM role a workload runs as, for any of the platform's compute types.

What a caller needs to know:

- **The trust policy comes from `workload`**, not from an input that names a principal. An ECS task role can be assumed by ECS tasks and nothing else. Where the service supports it, the trust is limited to this account with `aws:SourceAccount`.
- **The permission boundary is required.** There is no way to create a workload role without one.
- **Permissions are inline policies**, passed as JSON keyed by a short name that says what each allows. One policy per capability keeps a review readable: `read-own-parameters`, `consume-goods-received-queue`.
- **Wide managed policies are refused**: `AdministratorAccess`, `PowerUserAccess` and anything ending in `FullAccess`.
- **`workload = "ec2"` also creates an instance profile** with the same name.

| `workload` | Trusted service |
| --- | --- |
| `ecs-task` | `ecs-tasks.amazonaws.com` |
| `lambda` | `lambda.amazonaws.com` |
| `eks-pod` | `pods.eks.amazonaws.com` (EKS Pod Identity) |
| `ec2` | `ec2.amazonaws.com` |
| `step-functions` | `states.amazonaws.com` |
| `scheduler` | `scheduler.amazonaws.com` |
| `firehose` | `firehose.amazonaws.com` |

See the [access model](../../../docs/architecture/access-model.md#workload-roles).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

data "aws_iam_policy_document" "read_own_parameters" {
  statement {
    sid       = "ReadOwnConfiguration"
    actions   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:eu-west-1:333333333333:parameter${module.context.ssm_path}/*"]
  }
}

module "workload_role" {
  source = "../.."

  name        = "${module.context.prefix}-task-role"
  tags        = module.context.tags
  description = "Runs the catalog service on ECS."
  workload    = "ecs-task"
  account_id  = "333333333333"

  permissions_boundary_arn = "arn:aws:iam::333333333333:policy/meridian-prod-workload-boundary"

  policies = {
    read-own-parameters = data.aws_iam_policy_document.read_own_parameters.json
  }
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
| account\_id | Account the workload runs in. Where the service supports it, the role can be assumed only on behalf of this account. | `string` | n/a | yes |
| description | What runs as this role, in one sentence. | `string` | n/a | yes |
| name | Name of the role, for example meridian-prod-catalog-task-role. Build it from the context module's prefix. | `string` | n/a | yes |
| permissions\_boundary\_arn | ARN of the environment's permission boundary. Required: a workload role without a boundary is not allowed. | `string` | n/a | yes |
| tags | Tags for the role. Take them from the context module. | `map(string)` | n/a | yes |
| workload | Where the workload runs: ecs-task, lambda, eks-pod, ec2, step-functions, scheduler or firehose. Decides who may assume the role. | `string` | n/a | yes |
| managed\_policy\_arns | Managed policies to attach. Prefer inline policies written for the workload. AWS managed policies are usually wider than needed. | `set(string)` | `[]` | no |
| policies | Inline policies for the role, as JSON documents keyed by a short name that says what each allows. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_profile\_arn | ARN of the instance profile. Null unless the workload is ec2. |
| instance\_profile\_name | Name of the instance profile. Null unless the workload is ec2. |
| role\_arn | ARN of the role. Give it to the task definition, function, pod identity association or state machine. |
| role\_name | Name of the role, for attaching further policies from a service's own layer. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
<!-- END_TF_DOCS -->
