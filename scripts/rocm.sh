#!/usr/bin/env bash
# Run the rocm CLI with an isolated XDG_RUNTIME_DIR under ./.run (workspace-local, not $HOME).
set -euo pipefail

RUN_DIR="${MISE_PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/.run"
mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"

export XDG_RUNTIME_DIR="$RUN_DIR"

exec rocm "$@"
