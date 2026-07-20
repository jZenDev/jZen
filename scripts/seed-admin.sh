#!/usr/bin/env bash
# Create (or promote) a local admin user so you can log into the admin panel.
# Registers via the running backend, then flips its users.role to 'admin' in Postgres.
#
# Usage: scripts/seed-admin.sh [--email E] [--password P] [--port N]
#   defaults: admin@jzen.local / password123, backend on $ZEN_APP_PORT or 8085
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

EMAIL="admin@jzen.local"
PASSWORD="password123"
PORT="${ZEN_APP_PORT:-8085}"
while [ $# -gt 0 ]; do
  case "$1" in
    --email) EMAIL="$2"; shift ;;
    --password) PASSWORD="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done
API="http://localhost:${PORT}"

curl -sf "${API}/api/v1/health" >/dev/null 2>&1 \
  || die "Backend not reachable at ${API} (start it with scripts/admin.sh)."

info "Registering ${EMAIL} (ignored if it already exists)..."
curl -s -o /dev/null -H "Content-Type: application/json" -H "X-Zen-Transport: json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}" "${API}/api/v1/auth/register" || true

info "Promoting ${EMAIL} to admin in the users table..."
result=$(docker exec supabase_db_jzen psql -U postgres -d postgres -tAc \
  "UPDATE users SET role='admin' WHERE email='${EMAIL}' RETURNING email;")
[ -n "$result" ] || die "No users row for ${EMAIL} (did registration succeed?)."

info "Admin ready. Log in at http://localhost:5173"
info "  email:    ${EMAIL}"
info "  password: ${PASSWORD}"
