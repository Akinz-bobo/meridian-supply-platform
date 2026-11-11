# 0002: Develop and test against an AWS emulator

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #5         |

## Context

The platform uses more than thirty AWS services, including ones that are expensive to leave running: EKS control planes, NAT gateways, RDS instances, Kinesis shards. Provisioning three environments in real accounts for the life of the project would cost real money every hour, and anyone who wanted to try the repository would need an AWS account, credentials and a budget.

At the same time, infrastructure code that has never been applied is only a guess. It needs to be provisioned, exercised and destroyed, repeatedly, on every pull request.

LocalStack was the usual answer. In March 2026 its community edition was withdrawn: the image now requires an account and an auth token, and the free tier is limited to non-commercial use. A public repository that cannot be run without the reader's personal token is not reproducible.

A spike on 2026-11-11 provisioned and destroyed 34 resources with Terraform against [Floci](https://github.com/floci-io/floci) 2.4.0, an MIT-licensed emulator that needs no account. It covered VPC networking, S3, DynamoDB, SQS, SNS, KMS, IAM, Lambda, API Gateway, Secrets Manager, EventBridge, RDS, ECS behind a load balancer, EKS and EC2. RDS, ECS, EKS and EC2 ran as real containers (PostgreSQL, the task image, k3s), not stubs, and a request passed through API Gateway into Lambda and back.

## Decision

Floci is the default target for local development and for CI. The Terraform provider configuration switches between the emulator and real AWS through a single variable, and no module contains emulator-specific logic.

The emulator version is pinned. Upgrading it is a pull request like any other.

## Consequences

- Anyone can stand up the whole platform on a laptop with Docker, at no cost, and CI can provision the full stack on every pull request.
- Feedback is fast: a full apply takes minutes and nothing is left running afterwards.
- **The emulator is not AWS.** What it proves and what it does not must be stated wherever results are reported:

  | Proven                                                         | Not proven                                                      |
  | -------------------------------------------------------------- | --------------------------------------------------------------- |
  | The Terraform is valid and applies in dependency order         | Behaviour under real load, latency or throughput                |
  | Resources reference each other correctly                       | Real service quotas and limits                                  |
  | Services integrate: events flow, functions run, queries return | IAM enforcement in full, since emulators check policies loosely |
  | Application code works against AWS APIs                        | Real cost                                                       |
  | Destroy leaves nothing behind                                  | Multi-region and cross-account behaviour                        |

- Some features will be missing or behave differently. Each difference found is recorded in `docs/architecture/emulator-differences.md` with the workaround, and never hidden with a conditional in a module.
- No cost or performance figure in this repository comes from measurement on AWS. Cost estimates are calculated from public prices and labelled as estimates.
- The repository depends on a third-party project. If it is abandoned, the single switch variable and the absence of emulator logic in modules keep the cost of moving low.

## Alternatives considered

- **Real AWS accounts.** The only way to prove production behaviour, and the right next step for anyone adopting this. Rejected as the default because of cost and because it makes the repository unusable without an account.
- **LocalStack.** Requires an account and token, and its free tier excludes commercial use.
- **LocalStack 4.4.0, the last token-free release.** Works today, receives no fixes.
- **Moto.** A Python library for unit tests. It does not present a network endpoint that Terraform and several services in different languages can share in the same way, and it does not run real containers for EKS or RDS.
- **`terraform plan` only, never apply.** Catches syntax and reference errors but not ordering, integration or runtime problems. Plans are still produced, as a review artefact.
