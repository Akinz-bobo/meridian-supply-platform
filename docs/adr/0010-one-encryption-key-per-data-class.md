# 0010: One encryption key per data class

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-12 |
| Issue  | #19        |

## Context

Everything the platform stores is encrypted at rest with a customer managed KMS key, so that access to data can be controlled and audited separately from access to the service holding it. The question is how many keys.

A key is a unit of access control and a unit of blast radius. Whoever may use a key can read everything encrypted with it, and deleting or disabling it makes all of that unreadable. Each key also costs a fixed monthly fee and each API call is billed and recorded.

The platform will have around nine services, each with one or more stores, queues and log groups, in three environments.

## Decision

Each environment has **four keys, one per class of data**:

| Key         | Alias                            | Encrypts                                   |
| ----------- | -------------------------------- | ------------------------------------------ |
| `data`      | `alias/meridian-<env>-data`      | RDS, DynamoDB, ElastiCache, S3 buckets     |
| `logs`      | `alias/meridian-<env>-logs`      | CloudWatch log groups                      |
| `messaging` | `alias/meridian-<env>-messaging` | SQS queues, SNS topics, Kinesis streams    |
| `secrets`   | `alias/meridian-<env>-secrets`   | Secrets Manager secrets, secure parameters |

- Keys are created by the `foundation` layer with the `kms-key` module and published to Parameter Store under `/meridian/<env>/security/kms/`.
- Every key rotates yearly and has a 30 day deletion window.
- The key policy delegates access to IAM. A role may use a key only if its own policy says so, and the IAM foundations grant `kms:Decrypt` on a key to the roles that read that class of data.
- AWS services are named in a key policy only where a service must use the key itself (CloudWatch Logs for the `logs` key, and the services that deliver into encrypted queues for the `messaging` key), and are limited to requests made for this account.
- The Terraform state bucket keeps its own key in the shared account. It is created by the bootstrap stack before any environment exists.

## Consequences

- A role that can read application logs cannot, by that fact, decrypt a database or a secret. The classes line up with who needs access: operators read logs, services read data, and very few principals read secrets.
- Twelve keys across three environments. The cost is small and fixed, and does not grow with the number of services.
- All services share the `data` key within an environment. One service's role could decrypt another's table if its IAM policy also allowed reading that table. Separation between services therefore rests on resource policies and IAM, not on the key. This is the main thing given up.
- Disabling the `data` key in an emergency stops every service in that environment. That is drastic, and it is also a usable control: one action cuts off all access to data at rest.
- A service with stricter needs, such as one holding payment data, can be given a key of its own later without changing the others.

## Alternatives considered

- **One key per environment.** Cheapest and simplest. Rejected because it removes any distinction between reading logs and reading secrets.
- **One key per service.** Gives the strongest separation, and around forty keys. Rejected for now: the services are operated by one team, and the extra keys add policies to maintain without changing who can access what. The decision is easy to revisit per service.
- **One key per resource.** Hundreds of keys, each with its own policy. Rejected as unmanageable.
- **AWS managed keys (`aws/rds`, `aws/s3`).** Free, and their policies cannot be changed, so access cannot be restricted beyond the service's own permissions and cross-account use is impossible. Rejected.
