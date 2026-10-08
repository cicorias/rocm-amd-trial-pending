#!/usr/bin/env bash
# Build vLLM from source for this GPU's arch (gfx1152 / Radeon 860M) and install it into
# ./.vllm-gfx1152, a venv layered on top of rocm-cli's managed TheRock runtime.
#
# Why: the vLLM wheel `rocm engines install vllm` ships kernels for gfx1150/gfx1151 but not
# gfx1152, and under WSL the driver rejects foreign code objects (HSA_OVERRIDE_GFX_VERSION
# fails with hipErrorInvalidImage). Torch in the runtime already includes gfx1152.
#
# The venv reuses the runtime's torch and other deps through a .pth file, so rocm's runtime
# is never modified. Idempotent: re-running reuses the source checkout and rebuilds.
# serve:gpu:rocm:vllm points rocm at it with ROCM_CLI_VLLM_PYTHON.
set -euo pipefail

ROOT="${MISE_PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
VERSION="${VLLM_VERSION:-v0.26.0}"          # must match the runtime's torch (vLLM 0.26 pins torch 2.11)
ARCH="${VLLM_ROCM_ARCH:-gfx1152}"
SRC="$ROOT/.build/vllm-$VERSION"
WHEELS="$ROOT/.build/wheels"
VENV="$VLLM_VENV"
RUNTIME_SITE="$ROCM_RUNTIME_DIR/lib/python3.12/site-packages"
ROCM_INDEX="https://repo.amd.com/rocm/whl-multi-arch"

[ -d "$RUNTIME_SITE/torch" ] || { echo "rocm runtime torch not found under $RUNTIME_SITE" >&2; exit 1; }
SDK_VERSION=$("$ROCM_RUNTIME_DIR/bin/python" -I -c 'import importlib.metadata as m; print(m.version("rocm-sdk-core"))')

echo "==> venv $VENV (layered on $RUNTIME_SITE)"
[ -x "$VENV/bin/python" ] || uv venv --python "$ROCM_RUNTIME_DIR/bin/python" "$VENV"
echo "$RUNTIME_SITE" > "$VENV/lib/python3.12/site-packages/_rocm_runtime.pth"

echo "==> build tools + rocm-sdk-devel $SDK_VERSION (ROCm headers/cmake for $ARCH)"
uv pip install --python "$VENV/bin/python" \
  "cmake>=3.26.1" ninja "packaging>=24.2" "setuptools>=77.0.3,<80" "setuptools-scm>=8" \
  "setuptools-rust>=1.9.0" wheel jinja2 pip
uv pip install --python "$VENV/bin/python" --no-deps --index-url "$ROCM_INDEX" "rocm-sdk-devel==$SDK_VERSION"
# rocm-sdk-devel's files are relative symlinks into sibling _rocm_sdk_core/_rocm_sdk_libraries,
# which live in the runtime's site-packages; link them in beside it
for pkg in _rocm_sdk_core _rocm_sdk_libraries; do
  ln -sfn "$RUNTIME_SITE/$pkg" "$VENV/lib/python3.12/site-packages/$pkg"
done

ROCM_SDK_ROOT=$("$VENV/bin/python" -m rocm_sdk path --root)
CMAKE_DIR=$("$VENV/bin/python" -m rocm_sdk path --cmake)

echo "==> source $VERSION -> $SRC"
if [ ! -d "$SRC/.git" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" https://github.com/vllm-project/vllm.git "$SRC"
fi

echo "==> compiling vLLM for $ARCH (MAX_JOBS=${MAX_JOBS:-6}); this takes a while"
mkdir -p "$WHEELS"
(
  cd "$SRC"
  export VLLM_TARGET_DEVICE=rocm
  export PYTORCH_ROCM_ARCH="$ARCH"
  export ROCM_PATH="$ROCM_SDK_ROOT" ROCM_HOME="$ROCM_SDK_ROOT" HIP_PATH="$ROCM_SDK_ROOT"
  export CMAKE_PREFIX_PATH="$CMAKE_DIR"
  export PATH="$VENV/bin:$ROCM_SDK_ROOT/bin:$PATH"
  export MAX_JOBS="${MAX_JOBS:-6}"   # hipcc jobs need ~3-4 GB each; 30 GB RAM here
  "$VENV/bin/python" -m pip wheel . --no-build-isolation --no-deps -w "$WHEELS" -v 2>&1 \
    | tee "$ROOT/.build/vllm-build.log" | grep --line-buffered -E '^\[[0-9]+/[0-9]+\]|error|Error|Successfully built'
)

WHEEL=$(ls -t "$WHEELS"/vllm-*.whl | head -1)
echo "==> installing $(basename "$WHEEL")"
uv pip install --python "$VENV/bin/python" --no-deps --reinstall "$WHEEL"

echo "==> verifying kernels contain $ARCH"
SO=$(ls "$VENV"/lib/python3.12/site-packages/vllm/_C*.so | head -1)
# grep -c reads everything (grep -q would SIGPIPE strings and trip pipefail)
[ "$(strings "$SO" | grep -c "amdgcn-amd-amdhsa--$ARCH")" -gt 0 ] \
  || { echo "FAIL: $SO has no $ARCH code objects" >&2; exit 1; }
echo "OK: $(basename "$SO") includes $ARCH"
