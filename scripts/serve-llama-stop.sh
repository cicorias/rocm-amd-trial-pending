#!/usr/bin/env bash
# Stop the llama-server started by serve:cpu:llama or serve:gpu:llama (LLAMA_ALIAS = cpu-model | gpu-model).
# Matched on its binary, port and --alias, so it never touches the llama-server that `rocm serve`
# launches from the same runtime.
set -euo pipefail

PATTERN="^${LLAMA_SERVER_DIR}/llama-server .*--port ${SERVE_PORT} --alias ${LLAMA_ALIAS}( |$)"

if ! pkill -f "$PATTERN"; then
  echo "No ${LLAMA_ALIAS} llama-server running on port ${SERVE_PORT}"
  exit 0
fi
# pkill only sends SIGTERM; wait for the process to actually exit
for _ in $(seq 1 30); do
  pgrep -f "$PATTERN" >/dev/null || { echo "Stopped ${LLAMA_ALIAS} llama-server on port ${SERVE_PORT}"; exit 0; }
  sleep 0.5
done
pkill -KILL -f "$PATTERN" || true
echo "Killed ${LLAMA_ALIAS} llama-server on port ${SERVE_PORT} (did not exit on SIGTERM)"
