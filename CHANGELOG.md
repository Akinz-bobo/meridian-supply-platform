# Changelog

Notable changes, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org). A release is cut when a milestone closes.

## [Unreleased]

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

[Unreleased]: https://github.com/Akinz-bobo/meridian-supply-platform/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Akinz-bobo/meridian-supply-platform/releases/tag/v0.1.0
