#!/usr/bin/env bash
# Shared helpers for the jZen dev scripts. Source this ( . scripts/lib.sh ), do not execute it.
# Callers run with `set -euo pipefail` from the repo root.

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { printf "${GREEN}==>${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}==>${NC} %s\n" "$1"; }
die()  { printf "${RED}!! %s${NC}\n" "$1" >&2; exit 1; }

require_docker() { docker info >/dev/null 2>&1 || die "Docker is not running."; }

# Bring up the jZen Supabase stack and export SUPABASE_URL / SUPABASE_KEY for the backend.
# Frees another project's Supabase stack that shadows the local ports (54321/54322/...) and
# recovers a half-exited jZen stack (CLI says "running" but the db container has exited) with a
# stop before start.
ensure_supabase() {
  if ! supabase status >/dev/null 2>&1; then
    info "Starting Supabase..."
    docker ps --format '{{.ID}} {{.Names}}' | while read -r cid cname; do
      case "$cname" in
        *jzen*) : ;;
        supabase_*) warn "Freeing conflicting Supabase container ${cname}"; docker stop "$cid" >/dev/null ;;
      esac
    done
    supabase stop >/dev/null 2>&1 || true
    supabase start >/dev/null
  fi
  eval "$(supabase status -o env | sed 's/^/export SB_/')"
  export SUPABASE_URL="${SB_API_URL}"
  export SUPABASE_KEY="${SB_ANON_KEY}"
  info "Supabase up (${SUPABASE_URL})"
}

# Build the framework libs (install) + the demo backend jar (package).
build_backend() {
  info "Building framework libs + backend jar..."
  ( cd server && ./mvnw -B -q install -DskipTests )
  ( cd server && ./mvnw -B -q -f ../apps/zen_demo/zen_demo_server/pom.xml package -DskipTests )
}

BACKEND_JAR="apps/zen_demo/zen_demo_server/target/quarkus-app/quarkus-run.jar"

# Start the backend jar in the background on $1 (port), logging to $2. Sets BACKEND_PID.
start_backend() {
  local port="$1" log="$2"
  [ -f "$BACKEND_JAR" ] || die "No backend jar; run without --no-build first."
  info "Starting backend on :${port}..."
  java -Dquarkus.profile=dev -Dquarkus.http.port="${port}" -jar "$BACKEND_JAR" >"$log" 2>&1 &
  BACKEND_PID=$!
}

# Poll the backend health endpoint at $1 (base URL), tailing $2 (log) on failure.
wait_for_health() {
  local api="$1" log="${2:-}"
  printf "waiting for backend"
  for _ in $(seq 1 90); do
    curl -sf "${api}/api/v1/health" >/dev/null 2>&1 && { echo; info "Backend healthy: ${api}"; return 0; }
    printf "."; sleep 1
  done
  echo
  [ -n "$log" ] && tail -20 "$log"
  die "backend did not become healthy at ${api}"
}

# Kill whatever listens on port $1 (current user).
free_port() {
  local p="$1" pids
  pids=$(lsof -ti "tcp:${p}" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    info "Stopping port ${p} (PIDs: ${pids})"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  fi
}
