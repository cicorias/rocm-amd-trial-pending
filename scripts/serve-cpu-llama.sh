#!/usr/bin/env bash
# Phase 1: CPU-only server via the llama-server bundled with the rocm CLI's Lemonade runtime.
# `rocm serve` has no CPU fallback, so this bypasses it.
set -euo pipefail

export LD_LIBRARY_PATH="$LLAMA_SERVER_DIR:${LD_LIBRARY_PATH:-}"
# Hide GPUs so nothing silently falls onto a half-working ROCm backend
export HIP_VISIBLE_DEVICES=-1 ROCR_VISIBLE_DEVICES=-1

exec "$LLAMA_SERVER_DIR/llama-server" -hf "$CPU_MODEL_REPO" -ngl 0 \
  --host 127.0.0.1 --port "$SERVE_PORT" --alias cpu-model
