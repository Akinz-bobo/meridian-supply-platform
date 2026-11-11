#!/usr/bin/env bash
# Plans every layer of the given environments, checks each plan against the
# policies and writes a Markdown report.
#
# Usage: plan-report.sh <report-file> <environment> [environment ...]
# Exits non-zero if any plan fails or violates a policy. The report is
# written either way, so a failing pull request still shows why.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report="$1"
shift

# Plan files can contain secrets, so they live in a private temporary
# directory that is removed on exit.
work="$(mktemp -d)"
cleanup() {
  if [ -n "$work" ] && [ -d "$work" ]; then
    rm -rf -- "$work"
  fi
}
trap cleanup EXIT

failed=0
rows=""
details=""

for env in "$@"; do
  while IFS= read -r layer; do
    dir="$root/infra/environments/$env/$layer"
    plan="$work/$env-$layer"

    if ! make --no-print-directory -C "$root" init ENV="$env" LAYER="$layer" >"$plan.log" 2>&1 ||
      ! terraform -chdir="$dir" plan -input=false -lock=false -no-color \
        -var-file=../env.tfvars -out="$plan.bin" >>"$plan.log" 2>&1; then
      failed=1
      rows+="| \`$env\` | \`$layer\` | | | | | :x: plan failed |"$'\n'
      details+=$'\n'"<details><summary><code>$env/$layer</code>: plan failed</summary>"$'\n\n```\n'"$(tail -n 40 "$plan.log")"$'\n```\n\n</details>\n'
      continue
    fi
    terraform -chdir="$dir" show -json "$plan.bin" >"$plan.json"

    # A replacement is one delete and one create. It is counted once, as a replace.
    counts="$(jq -r '
      [.resource_changes[]?.change.actions] as $a
      | [
          ($a | map(select(. == ["create"])) | length),
          ($a | map(select(. == ["update"])) | length),
          ($a | map(select(index("delete") and index("create"))) | length),
          ($a | map(select(. == ["delete"])) | length)
        ] | @tsv' "$plan.json")"
    read -r add change replace destroy <<<"$counts"

    if policy_output="$(conftest test --no-color --policy "$root/infra/policies" \
      --data "$root/infra/policies/data" --all-namespaces "$plan.json" 2>&1)"; then
      policy=':white_check_mark: pass'
    else
      policy=':x: **fail**'
      failed=1
    fi
    warnings="$(grep -c '^WARN' <<<"$policy_output" || true)"
    if [ "$warnings" -gt 0 ]; then
      policy+=" ($warnings warning(s))"
    fi

    rows+="| \`$env\` | \`$layer\` | $add | $change | $replace | $destroy | $policy |"$'\n'

    changes="$(jq -r '
      .resource_changes[]?
      | select(.change.actions != ["no-op"] and .change.actions != ["read"])
      | (if (.change.actions | index("delete")) and (.change.actions | index("create")) then "replace"
         else .change.actions[0] end) as $verb
      | "\($verb | ascii_upcase)\t\(.address)"' "$plan.json" | sort)"
    findings="$(grep -E '^(FAIL|WARN)' <<<"$policy_output" | sed -E 's/^(FAIL|WARN) - [^ ]+ - /\1 /' || true)"

    if [ -n "$changes" ] || [ -n "$findings" ]; then
      details+=$'\n'"<details><summary><code>$env/$layer</code></summary>"$'\n'
      if [ -n "$changes" ]; then
        details+=$'\n```\n'"$changes"$'\n```\n'
      fi
      if [ -n "$findings" ]; then
        details+=$'\nPolicy findings:\n\n```\n'"$findings"$'\n```\n'
      fi
      details+=$'\n</details>\n'
    fi
  done < <("$root/scripts/layers.sh" "$env")
done

{
  echo '## Terraform plan'
  echo
  echo '| Environment | Layer | Add | Change | Replace | Destroy | Policy |'
  echo '| --- | --- | ---: | ---: | ---: | ---: | --- |'
  printf '%s' "$rows"
  printf '%s' "$details"
  echo
  echo '<sub>Planned against a local AWS emulator, starting from the state of the base branch. See docs/guides/pipeline.md for what that does and does not prove.</sub>'
} >"$report"

exit "$failed"
