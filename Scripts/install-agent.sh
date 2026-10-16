#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" -gt 1 || "${1:-}" == --* ]]; then
  echo 'Usage: bash Scripts/install-agent.sh [/absolute/PauseGuard.app]' >&2; exit 2
fi
app="${1:-$PWD/dist/PauseGuard.app}"
if [[ "$app" != /* || ! -x "$app/Contents/MacOS/PauseGuardAgent" ]]; then
  echo 'Build PauseGuard.app first and provide its absolute path.' >&2; exit 1
fi
if [[ "$EUID" -eq 0 ]]; then echo 'Run as the current logged-in user, without sudo.' >&2; exit 1; fi
exec "$app/Contents/MacOS/PauseGuardAgent" --install --app "$app"
