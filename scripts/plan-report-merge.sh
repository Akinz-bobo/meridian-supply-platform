#!/usr/bin/env bash
# Joins the plan reports of several environments into one.
#
# Usage: plan-report-merge.sh <output-file> <report-file> [report-file ...]
#
# The pipeline plans each environment in a job of its own and each writes a
# report with plan-report.sh. A pull request should still carry one plan
# comment, so the rows and the details of every report are collected under
# a single heading, in the order the files are given.
#
# A report that is missing means its job never got as far as planning. That
# is shown as a row, so an environment cannot silently drop out of the
# comment.
set -euo pipefail

output="$1"
shift

rows=""
details=""

for file in "$@"; do
  if [ ! -s "$file" ]; then
    # reports/plan-report-<environment>/plan-report.md
    environment="$(basename "$(dirname "$file")")"
    environment="${environment#plan-report-}"
    rows+="| \`$environment\` | | | | | | :x: no report. The job failed before it could plan |"$'\n'
    continue
  fi

  # Table rows start with a backticked environment name.
  rows+="$(grep -E '^\| `' "$file" || true)"$'\n'

  # Everything from the first details block up to the footnote.
  block="$(awk '/^<details>/ { on = 1 } /^<sub>/ { on = 0 } on' "$file")"
  if [ -n "$block" ]; then
    details+=$'\n'"$block"$'\n'
  fi
done

{
  echo '## Terraform plan'
  echo
  echo '| Environment | Layer | Add | Change | Replace | Destroy | Policy |'
  echo '| --- | --- | ---: | ---: | ---: | ---: | --- |'
  printf '%s' "$rows"
  printf '%s' "$details"
  echo
  echo '<sub>Planned against a local AWS emulator, starting from the state of the base branch. Each environment is planned in a job of its own. See docs/guides/pipeline.md for what that does and does not prove.</sub>'
} >"$output"
