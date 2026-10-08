#!/usr/bin/env bash
# Phase 2: GPU serving through `rocm serve` (TheRock ROCm). ROCM_ENGINE = lemonade (GGUF) | vllm (HF safetensors).
# rocm-cli's load limit: lemonade 2 min, hardcoded (engines/lemonade/src/process.rs:542);
# vllm 5 min default (engines/vllm/src/process.rs:33), overridable with ROCM_CLI_VLLM_READY_TIMEOUT_SECS.
# Override the model with GPU_MODEL. Runs as a managed service; stop with serve:gpu:rocm:stop.
# VLLM_GPU_MEMORY_UTILIZATION caps vLLM's share of the GPU: on this iGPU vLLM sees all 47.7 GiB of
# shared memory, and its 0.9 default reserves ~42 GiB of KV cache, then runs out of memory.
set -euo pipefail

extra=()
[ -n "${VLLM_GPU_MEMORY_UTILIZATION:-}" ] && extra+=(--gpu-memory-utilization "$VLLM_GPU_MEMORY_UTILIZATION")

exec rocm serve "${GPU_MODEL:-unsloth/gemma-4-26B-A4B-it-GGUF:Q4_K_M}" \
  --engine "${ROCM_ENGINE:-lemonade}" --port "$SERVE_PORT" --verbose "${extra[@]}"
