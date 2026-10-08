#!/usr/bin/env bash
# Phase 2b: GPU via the same bundled llama-server, offloading all layers (-ngl 99).
# Bypasses `rocm serve`, so there is no 2-minute load limit (gemma-4-26B takes ~5 min on the 860M).
set -euo pipefail

# Same runtime environment rocm serve gives it (rocm-cli engines/lemonade/src/process.rs);
# without TheRock's libs the HIP backend finds no GPU and silently runs on CPU.
export ROCM_PATH="$THEROCK_DIR"
export LD_LIBRARY_PATH="$LLAMA_SERVER_DIR:$THEROCK_DIR/lib:${LD_LIBRARY_PATH:-}"
export HIP_VISIBLE_DEVICES=0

exec "$LLAMA_SERVER_DIR/llama-server" -hf "${GPU_MODEL:-unsloth/gemma-4-26B-A4B-it-GGUF:Q4_K_M}" -ngl 99 \
  --host 127.0.0.1 --port "$SERVE_PORT" --alias gpu-model
