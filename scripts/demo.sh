#!/usr/bin/env bash
# Bring up the jZen reference app (zen_demo) in one shot: Supabase + backend + the Flutter client
# in Chrome. The script form of `task run:demo`, with the same robust Supabase handling as
# scripts/admin.sh.
#
# Usage: scripts/demo.sh [--no-build] [--port N] [--web-port N]
#   --no-build     reuse the existing backend jar
#   --port N       backend port (default: $ZEN_APP_PORT or 8085)
#   --web-port N   Flutter web port (default: $ZEN_WEB_PORT or 5200)
#
# The Flutter client runs in the foreground; Ctrl-C stops it and the backend it started.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

BUILD=1
PORT="${ZEN_APP_PORT:-8085}"
WEB_PORT="${ZEN_WEB_PORT:-5200}"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --port) PORT="$2"; shift ;;
    --web-port) WEB_PORT="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
export ZEN_APP_PORT="$PORT"
API="http://localhost:${PORT}"
LOG="scripts/.dev-backend.log"
# Let the browser's credentialed calls through CORS from the demo's web origin.
export CORS_ORIGINS="http://localhost:${WEB_PORT},http://localhost:8080,http://localhost:5173"
BACKEND_PID=""

cleanup() { [ -n "$BACKEND_PID" ] && kill "$BACKEND_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

require_docker
ensure_supabase
[ "$BUILD" -eq 1 ] && build_backend
start_backend "$PORT" "$LOG"
wait_for_health "$API" "$LOG"

info "Launching zen_demo (Flutter web) on http://localhost:${WEB_PORT} against ${API}"
( cd apps/zen_demo/zen_demo_client && flutter run -d chrome --web-port="${WEB_PORT}" \
    --dart-define=ZEN_ENV=dev --dart-define=ZEN_PLATFORM=web --dart-define=ZEN_API_URL="${API}" )
