# 0001: Record architecture decisions

|        |            |
| ------ | ---------- |
| Status | Accepted   |
| Date   | 2026-11-11 |
| Issue  | #5         |

## Context

This platform will be built over many milestones and will contain dozens of infrastructure modules and several services. Each embodies choices: which AWS service, which pattern, which trade-off. Months later the code shows what was chosen but not why, and not what was rejected.

Without that record, two things go wrong. Good decisions get reversed by someone who does not know the constraint that drove them. And poor decisions get preserved by someone who assumes there must have been a reason.

## Decision

We record every architecturally significant decision as a short Markdown file in `docs/adr`, numbered in sequence, using the format described by Michael Nygard: context, decision, consequences, with alternatives considered added.

A record is written in the same pull request as the change that implements the decision. Records are immutable once accepted, apart from their status. Changing a decision means writing a new record that supersedes the old one.

## Consequences

- The reasoning behind the system lives in the repository, versioned with the code it explains.
- Reviewing a pull request includes reviewing the decision, not only the diff.
- Writing a record takes time, and there is a judgement call about what counts as significant. The rule of thumb: expensive to reverse, constrains later work, or likely to be questioned.
- The index must be kept current. A check will enforce that every record is listed.

## Alternatives considered

- **A wiki or external document tool.** Drifts away from the code, has no review step and is not versioned with it.
- **Long comments in code.** Fine for local reasoning, but a decision that spans modules has no natural home in any one file.
- **Commit messages only.** They explain a change, not the alternatives, and are hard to find later.
