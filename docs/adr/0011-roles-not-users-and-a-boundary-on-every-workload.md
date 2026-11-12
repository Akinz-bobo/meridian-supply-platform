# 0011: Roles, not users, and a boundary on every workload role

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-12 |
| Issue  | #20        |

## Context

Three kinds of principal need access to an environment: the pipeline that applies Terraform, the people who operate and review it, and the workloads that run in it. Each can be given access in a way that leaves a long-lived secret somewhere, or in a way that does not.

There is a second problem. The pipeline must be able to create IAM roles, because every service brings its own. A principal that can create a role and attach any policy to it can give itself any permission. Left alone, "the pipeline can create roles" means "the pipeline is an administrator, and so is anyone who can change what the pipeline runs".

## Decision

**No IAM users and no access keys, anywhere.**

| Principal | How it authenticates                                                                                                                   | What it receives                                                   |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| Pipeline  | GitHub Actions presents a signed OpenID Connect token. The trust policy names this repository and one GitHub environment               | Credentials for the `deploy` role, valid for one hour              |
| People    | Sign in to a separate identity account, then assume a role in the environment, with multi-factor authentication no older than one hour | Credentials for the `operator` or `audit` role, valid for one hour |
| Workloads | The compute service assumes the workload's role for it                                                                                 | Credentials rotated by the service                                 |

**Every workload role carries a permission boundary**, one per environment. The boundary allows the platform's data-plane actions on resources named for that environment, in that region, and denies IAM, key administration and tampering with audit logs outright.

**The pipeline can create a role only if the role carries that boundary**, and cannot remove the boundary, change it, or change its own role and the other access roles. Those changes are applied by an administrator.

**Checks.** A policy check (`POL-IAM-4`) fails a plan that creates a role without a boundary. The three access roles are the recorded exceptions, each with its reason.

## Consequences

- There is no credential to leak from a laptop, a CI secret store or an image. The longest any credential lives is an hour.
- A fork's pull request cannot obtain the deploy role: the token's subject would name a different repository or no environment, and the trust policy matches the subject exactly, with no wildcard.
- A mistake in one service's policy is contained. With `Resource: "*"` written by accident, the role still reaches only its own environment's resources, because the boundary does not allow the rest.
- The pipeline cannot escalate. The worst role it can create is one limited by the boundary.
- Changing the boundary or the access roles needs a person with administrator access, outside the pipeline. This is deliberate friction on the most sensitive part of the system, and it means those changes are not exercised by the pipeline against a real account.
- The boundary relies on the naming standard. A resource that does not start with `<project>-<environment>-` is invisible to every workload. The policy checks `POL-NAME-1` to `POL-NAME-5` therefore protect access as well as tidiness.
- The deploy policy still lists whole services, because Terraform manages every resource type. That is a recorded exception to `POL-IAM-2`, limited by region and by the denies above.

## Alternatives considered

- **An IAM user with access keys for the pipeline.** Simple and universal. Rejected: a long-lived key stored as a CI secret is the most commonly leaked credential there is.
- **IAM users for people.** Rejected for the same reason, and because access would have to be removed in every account when someone leaves.
- **No boundary, careful review of every role.** Review catches most mistakes and not all of them, and does nothing against a compromised pipeline.
- **A service control policy instead of a boundary.** Stronger, because it cannot be removed from inside the account at all. It needs AWS Organizations, which the emulator does not model and a single-account evaluation cannot use. A real deployment should add service control policies on top. The boundary is the control that can be defined, tested and shown here.
