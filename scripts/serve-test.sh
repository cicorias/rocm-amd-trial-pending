#!/usr/bin/env bash
# Smoke-test whichever server is on SERVE_PORT with a chat completion against its first model.
set -euo pipefail

BASE="http://127.0.0.1:${SERVE_PORT}/v1"
MODEL=$(curl -sS --fail-with-body "$BASE/models" | python3 -c 'import json, sys; print(json.load(sys.stdin)["data"][0]["id"])')
echo "model: $MODEL"

curl -sS --fail-with-body "$BASE/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hi in 5 words.\"}],\"max_tokens\":256}"
echo
