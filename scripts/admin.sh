#!/usr/bin/env bash
# Bring up the jZen admin dev stack in one shot: Supabase + backend + admin panel.
#
# Usage: scripts/admin.sh [--no-build] [--port N]
#   --no-build   reuse the existing backend jar (skip the Maven build)
#   --port N     backend port (default: $ZEN_APP_PORT or 8085, dodging a leftover :8080 stack)
#
# The admin dev server runs in the foreground; Ctrl-C stops it and the backend it started.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

BUILD=1
PORT="${ZEN_APP_PORT:-8085}"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) BUILD=0 ;;
    --port) PORT="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
export ZEN_APP_PORT="$PORT"
API="http://localhost:${PORT}"
LOG="scripts/.dev-backend.log"
BACKEND_PID=""

cleanup() { [ -n "$BACKEND_PID" ] && kill "$BACKEND_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

require_docker
ensure_supabase
[ "$BUILD" -eq 1 ] && build_backend
start_backend "$PORT" "$LOG"
wait_for_health "$API" "$LOG"

# Vite proxies /api to the backend on $ZEN_APP_PORT (same-origin, so the session cookie flows).
info "Starting admin panel on http://localhost:5173 (proxies /api to ${API})"
info "Need a login? Run scripts/seed-admin.sh in another shell."
( cd apps/zen_demo/zen_demo_admin && pnpm dev )
