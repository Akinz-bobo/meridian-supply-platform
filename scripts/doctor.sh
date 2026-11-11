#!/usr/bin/env bash
# Checks that the tools this repository needs are installed and recent enough.
# Exits non-zero if a required tool is missing or too old.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

# version_ge <have> <need>: true when <have> is at least <need>.
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# first_version <text>: the first thing in <text> that looks like a version number.
first_version() {
  grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$1" | head -n1
}

# check <required|optional> <name> <minimum> <note> <version command...>
check() {
  local level=$1 name=$2 minimum=$3 note=$4
  shift 4
  local output version
  if ! command -v "$1" >/dev/null 2>&1; then
    if [ "$level" = required ]; then
      printf '  %-4s %-16s %-12s %s\n' 'FAIL' "$name" 'missing' "needs >= $minimum. $note"
      failures=$((failures + 1))
    else
      printf '  %-4s %-16s %-12s %s\n' '-' "$name" 'missing' "$note"
    fi
    return
  fi
  output="$("$@" 2>&1 | head -n3)"
  version="$(first_version "$output")"
  if [ -z "$version" ]; then
    printf '  %-4s %-16s %-12s %s\n' 'ok' "$name" 'unknown' 'installed, version not detected'
  elif version_ge "$version" "$minimum"; then
    printf '  %-4s %-16s %-12s\n' 'ok' "$name" "$version"
  elif [ "$level" = required ]; then
    printf '  %-4s %-16s %-12s %s\n' 'FAIL' "$name" "$version" "needs >= $minimum"
    failures=$((failures + 1))
  else
    printf '  %-4s %-16s %-12s %s\n' 'old' "$name" "$version" "needs >= $minimum. $note"
  fi
}

terraform_pin="$(cat "$root/.terraform-version")"

echo 'Required now'
check required docker 24.0 'https://docs.docker.com/engine/install/' docker --version
check required 'docker compose' 2.20 'Ships with current Docker.' docker compose version
check required terraform "$terraform_pin" 'Pinned in .terraform-version.' terraform version
check required aws 2.13 'AWS CLI v2.' aws --version
check required make 4.0 '' make --version
check required curl 7.0 '' curl --version
check required jq 1.6 '' jq --version
check required python3 3.10 'Used by the documentation checks.' python3 --version
check required tflint 0.60 'Install with: make tools' tflint --version
check required trivy 0.60 'Install with: make tools' trivy --version
check required conftest 0.60 'Install with: make tools' conftest --version

echo
echo 'Needed by later milestones'
check optional terraform-docs 0.17 'Milestone 1: module documentation.' terraform-docs --version
check optional kubectl 1.29 'Milestone 5: EKS.' kubectl version --client
check optional helm 3.14 'Milestone 5: EKS workloads.' helm version --short
check optional ansible 2.15 'Milestone 5: the EC2 gateway.' ansible --version

echo
if docker info >/dev/null 2>&1; then
  echo '  ok   Docker daemon is reachable'
else
  echo '  FAIL Docker daemon is not reachable. Is it running, and are you in the docker group?'
  failures=$((failures + 1))
fi

echo
if ((failures > 0)); then
  echo "$failures required check(s) failed."
  exit 1
fi
echo 'All required tools are present.'
