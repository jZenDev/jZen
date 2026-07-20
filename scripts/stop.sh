#!/usr/bin/env bash
# Stop the jZen dev stack: backend, admin dev server, zen_demo web, and (optionally) Supabase.
#
# Usage: scripts/stop.sh [--supabase] [--port N]
#   --supabase   also run `supabase stop`
#   --port N     backend port to free (default: $ZEN_APP_PORT or 8085); 8080, 5173, 5200 always freed
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

STOP_SUPABASE=0
PORT="${ZEN_APP_PORT:-8085}"
while [ $# -gt 0 ]; do
  case "$1" in
    --supabase) STOP_SUPABASE=1 ;;
    --port) PORT="$2"; shift ;;
    *) shift ;;
  esac
  shift
done

free_port "$PORT"   # backend (ZEN_APP_PORT)
free_port 8080      # backend (Quarkus dev default)
free_port 5173      # admin vite dev server
free_port 5200      # zen_demo flutter web

if [ "$STOP_SUPABASE" -eq 1 ]; then
  info "Stopping Supabase..."
  supabase stop >/dev/null 2>&1 || true
fi
info "Done."
