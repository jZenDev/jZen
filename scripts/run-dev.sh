#!/usr/bin/env bash
# The process-orchestration half of `task run:dev` (Taskfile.app.yml). Lives in a real
# bash script, not the task body, for one reason: go-task's shell (mvdan/sh) rejects
# `trap … INT` and `set -m`, so an inline task body can only ever clean up from an EXIT
# trap that fires after the foreground `flutter run` has already returned — i.e. after a
# SECOND Ctrl-C. That made the "one Ctrl-C tears it all down" promise false (issue #83).
#
# Here, with real bash (works on the macOS system bash 3.2, like the other scripts):
#   * `set -m` puts each backgrounded child (server, client) in its OWN process group,
#     so a Ctrl-C at the terminal is delivered to THIS script only, never straight to
#     the children. The children stop because `stop_all` stops them, in order — not
#     because a raw SIGINT won a race, and not after a second signal.
#   * `trap … INT TERM` sets a flag; the wait is a poll loop that checks it every second
#     (bash 3.2's `wait <pid>` is not interruptible by a trapped signal, so we don't use
#     it as the blocking primitive). First signal → flag set → loop breaks → stop_all.
#
# The task computes every value and hands it over as environment; this script does no
# path or platform inference of its own.
#
#   RUN_DEV_PORT          backend port
#   RUN_DEV_API           backend base URL (http://localhost:$PORT)
#   RUN_DEV_POM           app server pom.xml (absolute)
#   RUN_DEV_JZEN_DIR      jZen checkout root (for server/mvnw)
#   RUN_DEV_CLIENT_DIR    app client package dir (absolute)
#   RUN_DEV_FLUTTER_ARGS  extra `flutter run` args, space-separated (device flags)
#   RUN_DEV_DEFINES       --dart-define flags, space-separated
# SUPABASE_URL / SUPABASE_KEY / CORS_ORIGINS are inherited from the task's environment.
set -euo pipefail

: "${RUN_DEV_PORT:?}" "${RUN_DEV_API:?}" "${RUN_DEV_POM:?}"
: "${RUN_DEV_JZEN_DIR:?}" "${RUN_DEV_CLIENT_DIR:?}"

client_pidfile="$(mktemp "${TMPDIR:-/tmp}/zen-run-dev-client.XXXXXX")"
server_pid=""
client_pid=""
signalled=0
stopped=0

on_signal() { signalled=1; }

# Client from its --pid-file (TERM, then KILL); then the quarkus:dev java by its port
# system-property (a forked child of the backgrounded mvnw), then a port-scoped lsof
# fallback that waits for the port to free, escalating to SIGKILL.
stop_all() {
  [ "$stopped" -eq 1 ] && return
  stopped=1
  trap - INT TERM EXIT
  echo
  echo "==> run:dev: stopping client and server"
  echo "    Supabase is left running — stop it with 'task stop:supabase'"

  cp=$(cat "${client_pidfile}" 2>/dev/null || true)
  # `set -m` made each child a process-group leader (pgid == pid), so a negative pid
  # signals the whole subtree — the flutter tool and its dartaotruntime, the mvnw
  # wrapper and its forked JVM.
  for target in "${cp}" "${client_pid}" "${server_pid}"; do
    [ -n "${target}" ] || continue
    kill -TERM "-${target}" 2>/dev/null || kill -TERM "${target}" 2>/dev/null || true
  done

  pkill -f "quarkus.http.port=${RUN_DEV_PORT}" 2>/dev/null || true
  p=$(lsof -nP -iTCP:"${RUN_DEV_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)
  [ -n "${p}" ] && kill "${p}" 2>/dev/null || true
  for _ in $(seq 1 15); do
    lsof -nP -iTCP:"${RUN_DEV_PORT}" -sTCP:LISTEN -t >/dev/null 2>&1 || break
    sleep 1
  done
  p=$(lsof -nP -iTCP:"${RUN_DEV_PORT}" -sTCP:LISTEN -t 2>/dev/null || true)
  [ -n "${p}" ] && kill -9 "${p}" 2>/dev/null || true
  for target in "${cp}" "${client_pid}"; do
    [ -n "${target}" ] || continue
    kill -9 "-${target}" 2>/dev/null || kill -9 "${target}" 2>/dev/null || true
  done
  rm -f "${client_pidfile}"
}
trap on_signal INT TERM
trap stop_all EXIT

# `set -m`: each `&` below lands in its own process group, so a terminal Ctrl-C hits
# only this script and `stop_all` (via the flag) owns the teardown.
set -m

( cd "${RUN_DEV_JZEN_DIR}/server" && ./mvnw -B -q install -DskipTests \
  && "${RUN_DEV_JZEN_DIR}/server/mvnw" -f "${RUN_DEV_POM}" quarkus:dev \
       -Dquarkus.http.port="${RUN_DEV_PORT}" ) &
server_pid=$!
disown "${server_pid}" 2>/dev/null || true   # keep the pgroup, drop the job-exit chatter

ready=0
for _ in $(seq 1 90); do
  kill -0 "${server_pid}" 2>/dev/null || break
  [ "$signalled" -eq 1 ] && break
  if curl -sf "${RUN_DEV_API}/api/v1/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1 || true
done
[ "$signalled" -eq 1 ] && exit 0
[ "${ready}" -eq 1 ] || { echo "server did not become healthy on ${RUN_DEV_API}"; exit 1; }

cd "${RUN_DEV_CLIENT_DIR}"
# stdin closed: no interactive r/R/q keys (use `task run:client` for a hot-reload loop).
# --pid-file gives stop_all a real PID. The client is backgrounded so `set -m` isolates
# its process group too; the poll loop below is the interruptible wait.
# shellcheck disable=SC2086
flutter run ${RUN_DEV_FLUTTER_ARGS:-} ${RUN_DEV_DEFINES:-} \
  --pid-file="${client_pidfile}" < /dev/null &
client_pid=$!
disown "${client_pid}" 2>/dev/null || true

while kill -0 "${client_pid}" 2>/dev/null; do
  [ "$signalled" -eq 1 ] && break
  sleep 1 || true
done
