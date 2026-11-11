# 0004: Keep infrastructure, services and documentation in one repository

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #5         |

## Context

The platform consists of Terraform modules, environment definitions, several application services in more than one language, Lambda functions, Helm charts, pipelines and documentation. These could live in one repository or be split, for example one per service plus one for infrastructure.

The parts change together. Adding a queue means a module change, an environment change, a producer change in one service, a consumer change in another and an update to the event catalogue. The team is small.

## Decision

Everything lives in one repository with a fixed top-level layout:

```
infra/        Terraform: bootstrap, modules, environments, policies
services/     Application services, one directory each
functions/    Lambda functions
deploy/       Helm charts and GitOps manifests
docs/         Architecture, decisions, runbooks, planning
scripts/      Developer and CI tooling
```

CI uses path filters so that a change runs only the pipelines it affects.

## Consequences

- A change that spans infrastructure and code is one pull request, reviewed and merged atomically. There is no window in which the repositories disagree.
- One place for issues, milestones, documentation and history.
- Shared tooling and conventions are defined once.
- CI needs path filtering to stay fast, and the pipelines are more involved than in a single-purpose repository.
- Access control is all or nothing. Anyone who can read a service can read the infrastructure. Acceptable for this team size, and a reason to revisit if that changes.
- Versioning is for the repository as a whole. Individual modules are not released separately, so they cannot be consumed elsewhere at a pinned version without further work.

## Alternatives considered

- **One repository per service, plus one for infrastructure.** Gives teams independence and separate access control. For a small team it mostly adds coordination: cross-cutting changes need several pull requests merged in the right order.
- **Infrastructure modules in a separate, versioned repository.** The right move once several products share the modules. Premature while there is one consumer.
