# Changelog

Notable changes, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org). A release is cut when a milestone closes.

## [Unreleased]

### Added

- Messaging: a `messaging` state layer, a tested `event-bus` module with an archive, an event log and a publish policy per producer, and the event envelope as JSON Schema with a dependency-free validator and `make contract-test`.
- Consumer queues: a tested `event-consumer-queue` module (queue, dead-letter queue, rule, alarm and a consume policy), and the first three queues in every environment.
- Topics: a tested `notification-topic` module, an alarms topic that every dead-letter queue alarm notifies, and a notifications topic fed by a rule for the events meant for people.

## [0.4.0] - 2026-11-12

Milestone 3: data layer. The stores the services will use, each encrypted, protected against deletion and exercised through its API on every pull request, with no stored credential anywhere in the layer.

### Added

- Data layer: a `data` state layer in every environment that reads the foundation from Parameter Store, the data architecture document with classification, retention and recovery targets, and policy rule POL-TAG-4.
- Object storage: a tested `data-bucket` module with access policies as outputs, and the supplier uploads bucket in every environment.
- DynamoDB: a tested `dynamodb-table` module with access policies as outputs, the movement ledger and stock level tables in every environment, the inventory data model, and `make data-check`, which exercises the key design in the pipeline.
- Pipeline: each environment is rehearsed in a parallel job with its own emulator, the three plan reports are joined into one comment, and the Terraform setup is a shared composite action.
- PostgreSQL: a tested `postgres-database` module with RDS-managed credentials, enforced TLS, backups and logs, the catalog database in every environment, a database check in `make data-check`, and policy rules POL-DB-1 to POL-DB-5.
- Cache: a tested `redis-cache` module running Valkey with IAM-authenticated users and no shared password, the stock cache in every environment, a check of the access rule against a real Valkey server, and policy rules POL-CACHE-1 to POL-CACHE-4.
- Backups: a tested `backup-plan` module with a locked vault and selection by tag, a vault with its own key in every environment, daily backups of the catalog database and the movement ledger, a backup check in `make data-check`, and a restore runbook.
- The threat model now covers the data stores, and a data layer review records seven findings, each fixed or tracked.

### Fixed

- The security scan evaluated environment layers with their variables unknown, because the scanner does not follow the symbolic link to the shared variables file. It now scans a copy with links resolved.
- The table write policy no longer lists an IAM action that does not exist, and the movement ledger has an append-only policy.

## [0.3.0] - 2026-11-12

Milestone 2: network and security baseline. The network, encryption keys, identity and secrets that every workload will depend on, reviewed as a whole against a threat model before anything is built on top.

### Added

- Network: a tested `vpc` module with public, private and isolated data tiers across three zones, added to every environment and published to Parameter Store, with network checks in the smoke test, policy rule POL-NAME-5 and a network architecture document.
- VPC endpoints and flow logs: tested `vpc-endpoints` and `vpc-flow-logs` modules in every environment, smoke checks for both, and policy rules POL-LOG-1 and POL-LOG-2 for log retention.
- Security group baseline: a tested `tier-security-groups` module giving each tier one group linked by group reference, smoke checks, and policy rules POL-SG-1 and POL-SG-2.
- Encryption: a tested `kms-key` module, four keys per environment (data, logs, messaging, secrets), flow logs encrypted with the logs key, the encryption standard, decision record 0010, and policy rules POL-KMS-1, POL-KMS-2 and POL-LOG-3.
- IAM foundations: tested `permission-boundary`, `workload-role`, `access-roles` and `account-baseline` modules, the access model document, decision record 0011, and policy rules POL-IAM-4 and POL-IAM-5 with a recorded exception mechanism.
- Secrets and configuration: a tested `service-config` module that keeps secret values out of Terraform state with ephemeral and write-only arguments, apply tests against the emulator (`make test-emulator`), a state audit (`make state-audit`) in the pipeline, the secrets and configuration convention, and policy rules POL-SECRET-1 to POL-SECRET-3.
- A threat model for the network and identity layers, and a baseline review of every milestone 2 module that produced twelve findings, each fixed or tracked in an issue.

### Fixed

- Review fixes for the network: every VPC endpoint has a policy limited to this account, the flow logs module requires a customer managed key, and the data tier is no longer routed to gateway endpoints it could not use.
- Review fixes for identity: the permission boundary lists S3 actions exactly and denies deleting object versions, and the deploy role is denied disabling or deleting encryption keys outside a disposable environment.

## [0.2.0] - 2026-11-11

Milestone 1: infrastructure foundation. The first Terraform, and everything needed to change infrastructure safely: a local emulator, a layout for modules and environments, remote state, static analysis, policy as code and a pipeline.

### Added

- Local emulator stack: a pinned Floci in `compose.yaml`, `make up`, `down`, `status`, `logs` and `doctor`, a local development guide, and a CI job that proves the emulator boots.
- A record of emulator differences from AWS and how each is handled.
- Terraform layout: a `context` module for naming and tagging with tests, a shared provider configuration with one switch between the emulator and AWS, and the `foundation` state layer for dev, staging and production.
- `make plan`, `apply`, `destroy`, `validate` and `test`, and CI for formatting, validation and module tests.
- Decision record 0008: layered state per environment.
- Remote state: a tested `state-bucket` module, a bootstrap stack, a shared backend configuration with S3-native locking, `make bootstrap`, decision record 0009 and a state runbook.
- Static analysis: tflint with the AWS ruleset, trivy security scanning, optional pre-commit hooks, a checksum-verifying installer for pinned tools (`make tools`), `make lint`, `scan` and `check`, and CI jobs for both.
- Policy as code: 13 rules in Rego for tags, naming, approved regions, IAM and protected resources, with 39 tests, `make policy` and `make policy-test`, and a guide documenting each rule.
- Infrastructure pipeline: on a pull request, a plan against the base branch's state, a policy check, a plan comment and an apply-and-destroy rehearsal. On merge, an apply of dev, staging and production in order, each gated by a smoke test.
- Module standards, generated module READMEs (`make docs`, `make docs-check`), a usage example per module, and `make module` to create a module skeleton.

### Fixed

- An unused data source in the state bucket module, found by the linter.

## [0.1.0] - 2026-11-11

Milestone 0: planning and architecture. No infrastructure exists yet. This release is the written foundation everything else is built against.

### Added

- Delivery process: how a change moves from issue to `main`, the definitions of ready and done, bug handling, releases.
- Domain model with 25 numbered business rules and lifecycles for the supplier file, purchase order and batch, and a glossary.
- Architecture overview: system context, services and stores, three end-to-end flows, network tiers, security and observability approach, and a catalogue of every AWS service with its job.
- Event catalogue of 19 planned events with producers and consumers.
- Environment differences, naming standard, tagging standard and network address plan.
- Decision records 0001 to 0007: recording decisions, developing against an emulator, Terraform, a single repository, the compute model per workload, the event backbone and messaging conventions, and environments with account isolation.
- Roadmap with milestone order, dependencies and exit criteria.
- CI for documentation: formatting, relative links and the decision record index.

[Unreleased]: https://github.com/Akinz-bobo/meridian-supply-platform/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/Akinz-bobo/meridian-supply-platform/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Akinz-bobo/meridian-supply-platform/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Akinz-bobo/meridian-supply-platform/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Akinz-bobo/meridian-supply-platform/releases/tag/v0.1.0
