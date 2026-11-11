#!/usr/bin/env bash
# Blocks until the emulator answers its health endpoint, or fails after a timeout.
# Usage: wait-for-emulator.sh [timeout-seconds]
set -euo pipefail

endpoint="${AWS_ENDPOINT_URL:-http://localhost:${FLOCI_PORT:-4566}}"
timeout="${1:-90}"
deadline=$((SECONDS + timeout))

until curl --fail --silent --max-time 3 "${endpoint}/_floci/health" >/dev/null 2>&1; do
  if ((SECONDS >= deadline)); then
    echo "The emulator at ${endpoint} did not become healthy within ${timeout}s." >&2
    echo "Run 'make logs' to see why." >&2
    exit 1
  fi
  sleep 2
done

echo "Emulator is healthy at ${endpoint}."
