#!/usr/bin/env bash
# Phase 3: native Windows llama-server (upstream llama.cpp, Vulkan backend) on the Radeon 860M,
# launched from WSL through interop. Bypasses ROCm-on-WSL (/dev/dxg) entirely.
# Binds 127.0.0.1:SERVE_PORT on Windows; mirrored networking makes that the same loopback WSL
# and the wslc Open WebUI container (host.wslc.internal) already use.
#
# Installs the pinned release (WIN_LLAMA_BUILD) under %LOCALAPPDATA%\llama-vulkan on first run,
# and copies the GGUF from this repo's model cache to the Windows disk once, since a Windows
# process reading 16 GB over \\wsl$ is slow. Stop with serve:gpu:vulkan-win:stop.
set -euo pipefail

BUILD="$WIN_LLAMA_BUILD"
MODEL_REPO="${GPU_MODEL:-unsloth/gemma-4-26B-A4B-it-GGUF:Q4_K_M}"
WIN_ROOT="$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r')")/llama-vulkan"
BIN_DIR="$WIN_ROOT/$BUILD"

if [ ! -f "$BIN_DIR/llama-server.exe" ]; then
  zip="llama-$BUILD-bin-win-vulkan-x64.zip"
  echo "==> installing $zip -> $BIN_DIR"
  mkdir -p "$BIN_DIR"
  curl -fL --progress-bar -o "$WIN_ROOT/$zip" \
    "https://github.com/ggml-org/llama.cpp/releases/download/$BUILD/$zip"
  unzip -q -o "$WIN_ROOT/$zip" -d "$BIN_DIR"
  rm -f "$WIN_ROOT/$zip"
fi

# unsloth/gemma-4-26B-A4B-it-GGUF:Q4_K_M -> models--unsloth--gemma-4-26B-A4B-it-GGUF, *Q4_K_M*.gguf
repo="${MODEL_REPO%%:*}" quant="${MODEL_REPO##*:}"
src=$(find -L "$LLAMA_CACHE" -path "*models--${repo/\//--}/snapshots/*" -name "*${quant}*.gguf" 2>/dev/null | head -1)
[ -n "$src" ] || { echo "No $MODEL_REPO GGUF under $LLAMA_CACHE; run serve:gpu:llama once to download it" >&2; exit 1; }
dst="$WIN_ROOT/models/$(basename "$src")"
if [ ! -f "$dst" ] || [ "$(stat -c %s "$dst")" != "$(stat -L -c %s "$src")" ]; then
  echo "==> copying $(basename "$src") to the Windows disk (one time)"
  mkdir -p "$WIN_ROOT/models"
  cp -L "$src" "$dst.part" && mv "$dst.part" "$dst"
fi

echo "==> llama-server.exe $BUILD (Vulkan) on 127.0.0.1:$SERVE_PORT"
cd "$BIN_DIR"
exec ./llama-server.exe -m "$(wslpath -w "$dst")" -ngl 99 \
  --host 127.0.0.1 --port "$SERVE_PORT" --alias vulkan-model
