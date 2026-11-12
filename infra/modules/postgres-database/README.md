# postgres-database

A PostgreSQL database on RDS, with its subnet group, parameter group and log group.

Always on, whatever the caller passes:

| Protection | How |
| --- | --- |
| Private | Never publicly accessible. Placed in the subnets and security groups it is given |
| Encrypted at rest | Storage, snapshots and performance data use the customer managed key in `kms_key_arn` |
| Encrypted in transit | The parameter group sets `rds.force_ssl`, so a connection without TLS is refused |
| No password in Terraform | RDS creates the master password, stores it in Secrets Manager under `secrets_kms_key_arn` and rotates it. It is in neither the configuration nor the state |
| Backed up | Automated backups cannot be turned off. Retention is 1 to 35 days |
| Logged | Connections and slow statements are logged to a log group created with retention and the logs key |
| Classified | `data_classification` is required and becomes the `DataClassification` tag, copied to snapshots |

On by default, and inputs so that a disposable environment can relax them:

| Protection | Input | Default |
| --- | --- | --- |
| A standby in a second zone | `multi_az` | On |
| Two weeks of backups | `backup_retention_days` | 14 |
| Cannot be deleted | `deletion_protection` | On |
| A final snapshot on deletion | `skip_final_snapshot` | Off |

What a caller needs to know:

- **Read `address` and `port` from the outputs.** The module does not set the port, and nothing should assume 5432.
- **Applications do not use the master user.** Its secret is for administration and for creating application roles. IAM database authentication is on, so an application can connect with a short-lived token and hold no password. `resource_id` is what the IAM permission for that names.
- **The log group is created by the module, before the instance.** If RDS created it, it would have no retention and no customer managed key. Its name is the one RDS dictates, `/aws/rds/instance/<name>/postgresql`.
- **The master username cannot be `postgres`, `admin` or `root`.**
- **Storage grows by itself** up to `max_allocated_storage_gb`, a ceiling so that a runaway table fills a known amount.
- **Changes that need a restart wait for the maintenance window** unless `apply_immediately` is set.

The stores and their recovery targets are in the [data architecture](../../../docs/architecture/data.md).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
module "context" {
  source = "../../../context"

  environment = "prod"
  component   = "catalog"
}

module "postgres_database" {
  source = "../.."

  name          = "${module.context.prefix}-db"
  tags          = module.context.tags
  database_name = "catalog"

  data_classification = "confidential"

  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  security_group_ids = ["sg-0123456789abcdef0"]

  kms_key_arn         = "arn:aws:kms:eu-west-1:333333333333:key/11111111-1111-1111-1111-111111111111"
  secrets_kms_key_arn = "arn:aws:kms:eu-west-1:333333333333:key/22222222-2222-2222-2222-222222222222"
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
| data\_classification | How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag on the instance. | `string` | n/a | yes |
| database\_name | Name of the database created inside the instance. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts storage, snapshots and performance data. Pass the data key. | `string` | n/a | yes |
| logs\_kms\_key\_arn | ARN of the key that encrypts the database's log group. Pass the logs key. | `string` | n/a | yes |
| name | Identifier of the database instance, and the name of its subnet group and parameter group. Build it from the context module's prefix. | `string` | n/a | yes |
| secrets\_kms\_key\_arn | ARN of the key that encrypts the master password in Secrets Manager. Pass the secrets key. | `string` | n/a | yes |
| security\_group\_ids | Security groups attached to the database. Pass the data security group. | `list(string)` | n/a | yes |
| subnet\_ids | Subnets the database may be placed in. Pass the data subnets, in at least two zones. | `list(string)` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| allocated\_storage\_gb | Storage the database starts with, in gigabytes. | `number` | `20` | no |
| apply\_immediately | Apply changes that need a restart at once and not in the next maintenance window. Causes downtime on a single-zone instance. | `bool` | `false` | no |
| backup\_retention\_days | Days of automated backups, which is also how far back the database can be restored to a point in time. | `number` | `14` | no |
| backup\_window | Daily time, in UTC, when the automated backup is taken. | `string` | `"01:00-02:00"` | no |
| deletion\_protection | Refuse to delete the database. Turn off only in an environment whose data is disposable. | `bool` | `true` | no |
| engine\_version | PostgreSQL version, as a major version (16) or an exact one (16.4). With a major version, RDS chooses the minor version and upgrades it in the maintenance window. | `string` | `"16"` | no |
| instance\_class | Size of the instance. | `string` | `"db.t4g.medium"` | no |
| log\_retention\_days | How long the database's logs are kept. | `number` | `90` | no |
| maintenance\_window | Weekly time, in UTC, when patches and minor upgrades are applied. Must not overlap the backup window. | `string` | `"sun:03:00-sun:04:00"` | no |
| master\_username | Name of the master user. Its password is managed by RDS. | `string` | `"meridian_admin"` | no |
| max\_allocated\_storage\_gb | Storage the database may grow to by itself, in gigabytes. A ceiling, so that a runaway table fills a known amount and not the budget. | `number` | `100` | no |
| multi\_az | Keep a synchronous standby in a second zone and fail over to it automatically. | `bool` | `true` | no |
| performance\_insights | Record database load by statement, wait and user, kept for 7 days and encrypted with the data key. | `bool` | `true` | no |
| skip\_final\_snapshot | Delete the database without taking a last snapshot. Turn on only in an environment whose data is disposable. | `bool` | `false` | no |
| slow\_statement\_milliseconds | Log statements that take longer than this. | `number` | `1000` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| address | Host name to connect to. Read it together with port, and do not assume 5432. |
| arn | ARN of the database instance. |
| database\_name | Name of the database inside the instance. |
| identifier | Identifier of the database instance. |
| log\_group\_name | Log group that receives the database's logs. |
| master\_user\_secret\_arn | ARN of the secret that holds the master user's credentials. Managed and rotated by RDS. Applications do not use the master user. |
| port | Port to connect to. |
| resource\_id | Immutable identifier of the instance, used in the ARN that grants IAM database authentication: arn:aws:rds-db:<region>:<account>:dbuser:<resource\_id>/<user>. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
<!-- END_TF_DOCS -->
