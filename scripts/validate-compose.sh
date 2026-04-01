#!/usr/bin/env bash
set -euo pipefail

# Validate each compose file in `compose/` when merged with root `docker-compose.yml`.
# Usage: ./scripts/validate-compose.sh

ROOT_COMPOSE="$(dirname "$0")/.."/docker-compose.yml
COMPOSE_DIR="$(dirname "$0")/.."/compose

echo "Using root compose: $ROOT_COMPOSE"

failures=0
included_files="$(grep '^  - compose/' "$ROOT_COMPOSE" | awk '{print $2}' || true)"

printf '\nValidating root compose ...\n'
if docker compose -f "$ROOT_COMPOSE" config >/dev/null 2>&1; then
  printf '  OK\n'
else
  printf '  FAILED: docker compose config returned non-zero for root compose\n'
  failures=$((failures+1))
fi

for f in "$COMPOSE_DIR"/*.yml; do
  rel_path="compose/$(basename "$f")"
  if printf '%s\n' "$included_files" | grep -qx "$rel_path"; then
    printf '\nSkipping %s because it is already included by root compose ...\n' "$f"
    continue
  fi

  printf '\nValidating %s ...\n' "$f"
  if docker compose -f "$ROOT_COMPOSE" -f "$f" config >/dev/null 2>&1; then
    printf '  OK\n'
  else
    printf '  FAILED: docker compose config returned non-zero for %s\n' "$f"
    failures=$((failures+1))
  fi
done

if [ "$failures" -ne 0 ]; then
  printf '\nValidation completed with %s failure(s).\n' "$failures"
  exit 1
fi

printf '\nAll compose files validated successfully.\n'
