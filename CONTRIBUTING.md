# Contributing

This project follows the same process whether one person or ten are working on it. The full description is in the [delivery process](docs/planning/delivery-process.md). In short:

1. **Every change starts as an issue.** It states the problem, the scope and how we will know it is done.
2. **One branch per issue**, named `<type>/<issue-number>-<short-description>`, for example `feat/42-vpc-module`.
3. **Small commits** in [Conventional Commits](https://www.conventionalcommits.org) form: `feat(network): add private subnets per availability zone`.
4. **A pull request** that links the issue, explains what and why, and passes every check.
5. **Merge by rebase**, so `main` stays linear and every commit on it is meaningful.

## Ground rules

- `main` is always deployable. Nothing merges with a failing check.
- Infrastructure changes include the Terraform plan summary in the pull request.
- Significant decisions get a decision record in the same pull request as the change.
- Documentation is part of the change, not a follow-up.
- No secrets in the repository, ever. Not in code, not in history, not in examples.
- Bugs get an issue with steps to reproduce before they get a fix.

## Reporting security problems

Please do not open a public issue. Use **Security > Report a vulnerability** on this repository.
