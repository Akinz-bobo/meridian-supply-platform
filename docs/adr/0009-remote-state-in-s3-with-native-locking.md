# 0009: Keep state in one S3 bucket with native locking

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #11        |

## Context

Terraform state must be shared, encrypted, versioned and locked. [Decision record 0008](0008-layered-state-per-environment.md) splits state into layers, so there will be around fifteen state files: five layers in each of three environments.

Three questions follow.

**How is state locked?** For years the S3 backend locked through a DynamoDB table. Terraform 1.10 added locking with a lock object written beside the state using an S3 conditional write (`use_lockfile`), and the DynamoDB arguments are now deprecated.

**One bucket or several?** State could live in one bucket for the organisation or in a bucket per environment account.

**Where does the first state go?** The stack that creates the bucket cannot store its own state in a bucket that does not exist yet.

## Decision

- **Locking uses `use_lockfile`.** No DynamoDB table is created.
- **One bucket, in the shared-services account**, holds state for every environment. The key is `<environment>/<layer>/terraform.tfstate`.
- The bucket is private, encrypted with its own customer managed KMS key, versioned, and denies requests that are not over TLS or not KMS-encrypted. Old versions are kept for 90 days.
- **A bootstrap stack** (`infra/bootstrap`) creates the bucket and key. It is applied by hand, once, with local state. What happens to that state is covered in the [state runbook](../runbooks/terraform-state.md#the-bootstrap-state-is-lost).
- The backend block in every layer is empty. Bucket settings come from one shared file and the key is supplied at `init`, so no layer can point at the wrong key by copy and paste.

## Consequences

- One fewer resource type to create, pay for, monitor and grant access to. Locking and state share one access policy.
- Terraform 1.10 or later is required. The repository already pins a later version.
- State for production and for dev share a bucket. Isolation between them is by IAM on the key prefix, not by account. A role for the dev pipeline is granted `dev/*` only. That is weaker than a bucket per account and is a deliberate trade for a single place to audit, back up and protect. Granting those prefixes is part of the IAM foundations work.
- A lock left behind by a killed process is an object, and can be seen and removed with ordinary S3 tools as well as `terraform force-unlock`.
- The bootstrap state is the one piece of state not protected by the mechanism it creates. It is small, contains no secrets, and can be rebuilt by import.
- Every state version is retained for 90 days, so a bad apply can be undone by restoring the previous version.

## Alternatives considered

- **DynamoDB lock table.** Works, and is what most existing documentation shows. It is deprecated, and it is a second resource whose permissions must be kept in step with the bucket's.
- **A state bucket in each environment account.** Stronger isolation: production state is unreachable with dev credentials whatever the policy says. It triples the bootstrap, and the pipeline needs to know three backends. A reasonable choice for an organisation that weights isolation above simplicity, and cheap to move to because the backend is configured in one file.
- **HCP Terraform or another hosted backend.** State, locking, run history and policy in one service. It adds an external dependency and an account, which conflicts with the aim that anyone can run this repository with nothing but Docker.
- **Local state committed to Git.** No locking, secrets in history, and merge conflicts in a machine-written file.
