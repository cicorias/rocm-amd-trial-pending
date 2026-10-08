#!/usr/bin/env bash
# Stop the Windows llama-server.exe started by serve:gpu:vulkan-win (matched on its --alias).
set -euo pipefail

stopped=$(powershell.exe -NoProfile -Command '
  $p = Get-CimInstance Win32_Process |
       Where-Object { $_.Name -eq "llama-server.exe" -and $_.CommandLine -match "--alias vulkan-model" }
  $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  @($p).Count' | tr -d '\r')

if [ "${stopped:-0}" -gt 0 ]; then
  echo "Stopped Windows vulkan-model llama-server"
else
  echo "No Windows vulkan-model llama-server running"
fi
