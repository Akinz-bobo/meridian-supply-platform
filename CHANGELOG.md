# Changelog

Notable changes, newest first. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org). A release is cut when a milestone closes.

## [Unreleased]

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
