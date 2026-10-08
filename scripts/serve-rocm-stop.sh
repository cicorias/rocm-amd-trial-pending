#!/usr/bin/env bash
# Stop every running `rocm serve` managed service, whatever port it is on.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
ids=$("$SCRIPTS/rocm.sh" services list --json | python3 -c '
import json, sys
print("\n".join(s["service_id"] for s in json.load(sys.stdin)))
')

if [ -z "$ids" ]; then
  echo "No rocm services running"
fi
for id in $ids; do
  "$SCRIPTS/rocm.sh" services stop "$id" --yes
done

# `rocm serve` stays in the foreground after its service is stopped; end those launchers too
if pkill -f '^rocm serve '; then
  for _ in $(seq 1 20); do pgrep -f '^rocm serve ' >/dev/null || break; sleep 0.5; done
  echo "Stopped leftover rocm serve launcher(s)"
fi
