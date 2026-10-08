#!/usr/bin/env bash
# Open WebUI in a wslc container, pointed at the OpenAI-compatible endpoint from serve:cpu / serve:gpu.
# host.wslc.internal resolves to the host loopback, which (mirrored networking) reaches the 127.0.0.1-bound server.
set -euo pipefail

NAME="${WEBUI_NAME:-open-webui}"
wslc.exe remove -f "$NAME" >/dev/null 2>&1 || true

wslc.exe run -d --name "$NAME" \
  -p "${WEBUI_PORT:-3000}:8080" \
  -v open-webui:/app/backend/data \
  -e OPENAI_API_BASE_URL="http://host.wslc.internal:${SERVE_PORT}/v1" \
  -e OPENAI_API_KEY=none \
  -e ENABLE_OLLAMA_API=false \
  -e WEBUI_AUTH="${WEBUI_AUTH:-False}" \
  ghcr.io/open-webui/open-webui:main

URL="http://localhost:${WEBUI_PORT:-3000}"
echo "Waiting for Open WebUI to start..."
for _ in $(seq 1 60); do
  curl -sf -m2 "$URL/health" >/dev/null && break
  sleep 2
done

echo
echo "  Open in Edge:  $URL"
echo "  Model backend: http://host.wslc.internal:${SERVE_PORT}/v1 (start a serve:* task)"
echo "  Logs:          wslc.exe logs -f $NAME"
curl -sf -m2 "http://127.0.0.1:${SERVE_PORT}/v1/models" >/dev/null \
  || echo "  WARNING: nothing answering on port ${SERVE_PORT} yet, so the model list will be empty"
