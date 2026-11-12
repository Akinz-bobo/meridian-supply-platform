# redis-cache

A Redis-compatible cache on ElastiCache, running Valkey, with its subnet group, parameter group, users and slow log.

Always on, whatever the caller passes:

| Protection | How |
| --- | --- |
| Private | Placed in the subnets and security groups it is given. ElastiCache has no public endpoint |
| Encrypted at rest | The cache and its snapshots use the customer managed key in `kms_key_arn` |
| Encrypted in transit | Connections use TLS |
| No shared password | There is no auth token. Each client is a named user that authenticates with its IAM role |
| Least privilege inside the cache | Each user has an access string. One that grants every key, every command, or the admin or dangerous categories is refused at plan time |
| Evicts when full | `maxmemory-policy` cannot be `noeviction`, which would turn a full cache into failed writes |
| Classified | `data_classification` is required and becomes the `DataClassification` tag |

On by default, and inputs:

| Protection | Input | Default |
| --- | --- | --- |
| A replica in a second zone, with automatic failover | `replicas` | 1 |
| Daily snapshots, and a final one on deletion | `snapshot_retention_days` | 1 |

What a caller needs to know:

- **Users are the access model.** `users` maps a short name, usually a service, to an access string in Valkey ACL syntax: `on ~stock:* +@read +@write +@connection -@dangerous` lets a client read and write keys under `stock:` and nothing else. Give each client its own key prefix.
- **Attach `connect_policy_json[<name>]` to the client's workload role.** It allows `elasticache:Connect` to this cache as that one user. The client connects with the user id as its user name and an IAM token as its password, which a current Valkey or Redis client library generates.
- **A Valkey user group has no default user.** Nothing can connect without being one of the named users.
- **It is a cache.** Anything in it must be rebuildable from its source. Snapshots make a restart warm. They are not a backup.
- **Connect to `primary_endpoint_address` to write and `reader_endpoint_address` to read**, on `port`, with TLS.

The access string is tested against a real Valkey server by `make data-check`. See the [data architecture](../../../docs/architecture/data.md#cache-access).

<!-- BEGIN_TF_DOCS -->
## Usage

```hcl
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
```

## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.10.0, < 2.0.0 |
| aws | >= 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| account\_id | Account the cache is in. Used to name it exactly in the connect policies. | `string` | n/a | yes |
| data\_classification | How sensitive the contents are: public, internal, confidential or restricted. Becomes the DataClassification tag. | `string` | n/a | yes |
| description | What the cache holds, in one sentence. | `string` | n/a | yes |
| kms\_key\_arn | ARN of the key that encrypts the cache and its snapshots at rest. Pass the data key. | `string` | n/a | yes |
| log\_group\_name | Name of the log group for the slow log, a path under /<project>/<environment>/. | `string` | n/a | yes |
| logs\_kms\_key\_arn | ARN of the key that encrypts the slow log's log group. Pass the logs key. | `string` | n/a | yes |
| name | Identifier of the replication group, and the name of its subnet group, parameter group and user group. Build it from the context module's prefix. | `string` | n/a | yes |
| security\_group\_ids | Security groups attached to the cache. Pass the data security group. | `list(string)` | n/a | yes |
| subnet\_ids | Subnets the cache nodes may be placed in. Pass the data subnets. | `list(string)` | n/a | yes |
| tags | Tags for every resource in the module. Take them from the context module. | `map(string)` | n/a | yes |
| users | Clients of the cache, keyed by a short name such as the service. Each authenticates with IAM and is limited by an access string in Valkey ACL syntax, for example: on ~stock:* +@read +@write -@dangerous. | <pre>map(object({<br/>    access_string = string<br/>  }))</pre> | n/a | yes |
| apply\_immediately | Apply changes at once and not in the next maintenance window. | `bool` | `false` | no |
| engine\_version | Valkey version, as major.minor. | `string` | `"8.0"` | no |
| eviction\_policy | What happens when memory is full. The default evicts the least recently used key. | `string` | `"allkeys-lru"` | no |
| log\_retention\_days | How long the slow log is kept. | `number` | `90` | no |
| maintenance\_window | Weekly time, in UTC, when patches are applied. Must not overlap the snapshot window. | `string` | `"sun:03:00-sun:04:00"` | no |
| node\_type | Size of each node. | `string` | `"cache.t4g.small"` | no |
| replicas | Read replicas in other zones. With at least one, a failed primary is replaced automatically. Zero means an outage of the node is an outage of the cache. | `number` | `1` | no |
| snapshot\_retention\_days | Days of daily snapshots. Zero turns snapshots off, which suits a cache that is cheap to refill. | `number` | `1` | no |
| snapshot\_window | Daily time, in UTC, when the snapshot is taken. | `string` | `"01:00-02:00"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | ARN of the replication group. |
| connect\_policy\_json | IAM policy for each client, keyed by the short name. It lets a role connect as that one user. Attach it to the client's workload role. |
| port | Port to connect to. |
| primary\_endpoint\_address | Host name for writes. Connect with TLS. |
| reader\_endpoint\_address | Host name for reads, spread across replicas. Connect with TLS. |
| replication\_group\_id | Identifier of the replication group. |
| user\_ids | Cache user for each client, keyed by the short name. The client connects with this as its user name. |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.slow](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_elasticache_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_parameter_group) | resource |
| [aws_elasticache_replication_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | resource |
| [aws_elasticache_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [aws_elasticache_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_user) | resource |
| [aws_elasticache_user_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_user_group) | resource |
| [aws_iam_policy_document.connect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
<!-- END_TF_DOCS -->
