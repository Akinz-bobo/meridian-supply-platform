#!/usr/bin/env bash
# Posts a Markdown file as a comment on a pull request, replacing the
# comment from the previous run so a pull request has one plan, not ten.
#
# Usage: pr-comment.sh <pull-request-number> <markdown-file>
# Needs GH_TOKEN and GITHUB_REPOSITORY, which GitHub Actions provides.
set -euo pipefail

number="$1"
file="$2"
marker='<!-- meridian-plan-report -->'
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"

body="$(printf '%s\n\n%s\n' "$marker" "$(cat "$file")")"

existing="$(gh api "repos/$repo/issues/$number/comments" --paginate \
  --jq "[.[] | select(.body | startswith(\"$marker\"))][0].id // empty")"

if [ -n "$existing" ]; then
  jq -n --arg body "$body" '{body: $body}' |
    gh api --method PATCH "repos/$repo/issues/comments/$existing" --input - >/dev/null
  echo "Updated the plan comment on #$number."
else
  jq -n --arg body "$body" '{body: $body}' |
    gh api --method POST "repos/$repo/issues/$number/comments" --input - >/dev/null
  echo "Added a plan comment to #$number."
fi
