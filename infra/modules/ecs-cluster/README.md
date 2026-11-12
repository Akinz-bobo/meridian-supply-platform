# ecs-cluster

An ECS cluster for Fargate services, with container metrics and a recorded, encrypted trail of every shell session.

What a caller needs to know:

- **There are no servers.** On Fargate a cluster is a name that groups services and carries a few settings.
- **Container insights are on**, so a slow or leaking container can be told from a healthy one.
- **Shell sessions are recorded.** Opening a shell in a running container (`ecs execute-command`) is the most powerful access there is. Services leave it off. When it is switched on for an incident, every command and every line of output goes to the log group in `exec_log_group_name`, encrypted with the logs key and kept for a year.
- **On-demand capacity by default.** Spot is available to a service that asks for it and can tolerate being stopped with two minutes' notice.

Services are created with the [`ecs-service` module](../ecs-service/README.md). See [compute](../../../docs/architecture/compute.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "compute"
}

module "ecs_cluster" {
  source = "../.."

  name = module.context.prefix
  tags = module.context.tags

  exec_log_group_name = "${module.context.ssm_path}/ecs-exec"
  logs_kms_key_arn    = "arn:aws:kms:eu-west-1:333333333333:key/33333333-3333-3333-3333-333333333333"
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
| exec\_log\_group\_name | Name of the log group that records shell sessions in containers, a path under /<project>/<environment>/. | `string` | n/a | yes |
| logs\_kms\_key\_arn | ARN of the key that encrypts shell sessions and their log group. Pass the logs key. | `string` | n/a | yes |
| name | Name of the cluster. Build it from the context module's prefix. | `string` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| log\_retention\_days | How long records of shell sessions are kept. | `number` | `365` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the cluster. A service is created in it. |
| cluster\_name | Name of the cluster. |
| exec\_log\_group\_name | Log group that records shell sessions in containers. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.exec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
<!-- END_TF_DOCS -->
