#!/usr/bin/env bash
#
# Stop the Odoo servers running in the dev containers.
#
# Targets the `odoo-bin` processes started by ./scripts/start.sh (and any
# init-db.sh run that is still going). Test runners (./scripts/run-tests.sh,
# i.e. --test-enable) are LEFT ALONE unless you pass --all, so this is safe to
# use while a test suite is running in another terminal/session.
#
# By default it also stops the servers in the sibling instance's container
# (through ./scripts/dexec.sh), since both instances are usually up together.
#
# Usage:
#   ./scripts/kill.sh                 # this container + its sibling
#   ./scripts/kill.sh --local         # only this container
#   ./scripts/kill.sh --all           # also kill running test runners
#   ./scripts/kill.sh --timeout 30    # SIGTERM grace period (default 10s)
set -uo pipefail

ALL=""
LOCAL=""
TIMEOUT=10
while [ $# -gt 0 ]; do
  case "$1" in
    -a|--all)     ALL=1 ;;
    -l|--local)   LOCAL=1 ;;
    -t|--timeout) TIMEOUT="${2:?--timeout needs a value}"; shift ;;
    -h|--help)    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "!! Unknown argument '$1' (see --help)" >&2; exit 2 ;;
  esac
  shift
done

# --- which odoo processes are ours to kill ---------------------------------
# One pid per line. A match must really BE an odoo-bin process — argv[0] is the
# interpreter and argv[1] the script (or argv[0] is odoo-bin itself). Matching
# the whole command line would also hit shells and editors that merely mention
# odoo-bin. Test runners are skipped unless --all.
odoo_pids() {
  local pid argv0 argv1 cmd
  for pid in $(pgrep -f 'odoo-bin' 2>/dev/null); do
    [ "${pid}" = "$$" ] && continue
    [ -r "/proc/${pid}/cmdline" ] || continue
    argv0=$(tr '\0' '\n' < "/proc/${pid}/cmdline" | sed -n 1p)
    argv1=$(tr '\0' '\n' < "/proc/${pid}/cmdline" | sed -n 2p)
    case "${argv0##*/}" in
      odoo-bin|odoo) ;;
      python*) [ "${argv1##*/}" = "odoo-bin" ] || continue ;;
      *) continue ;;
    esac
    cmd=$(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null) || continue
    if [ -z "${ALL}" ] && [[ "${cmd}" == *--test-enable* ]]; then
      echo "-- skipping test runner (pid ${pid}); use --all to kill it too" >&2
      continue
    fi
    echo "${pid}"
  done
}

PIDS=$(odoo_pids)
if [ -z "${PIDS}" ]; then
  echo ">> No Odoo server running in this container ($(hostname))"
else
  for pid in ${PIDS}; do
    echo ">> Stopping pid ${pid}: $(tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null | cut -c1-120)"
  done
  # shellcheck disable=SC2086
  kill -TERM ${PIDS} 2>/dev/null

  still=""
  waited=0
  while [ "${waited}" -lt "${TIMEOUT}" ]; do
    still=""
    for pid in ${PIDS}; do kill -0 "${pid}" 2>/dev/null && still+=" ${pid}"; done
    [ -z "${still}" ] && break
    sleep 1
    waited=$((waited + 1))
  done

  if [ -n "${still}" ]; then
    echo "!! Still alive after ${TIMEOUT}s, sending SIGKILL:${still}"
    # shellcheck disable=SC2086
    kill -KILL ${still} 2>/dev/null
    sleep 1
  fi
  echo ">> Done ($(hostname))"
fi

# --- sibling instance -------------------------------------------------------
[ -n "${LOCAL}" ] && exit 0

# Which instance are we? The config filename carries the role.
case "$(basename "${ODOO_RC:-}")" in
  odoo.custom.conf) SIBLING=partena_client ;;
  odoo.client.conf) SIBLING=partena_custom ;;
  *) echo ">> Unknown instance role (ODOO_RC=${ODOO_RC:-unset}); not touching the sibling"; exit 0 ;;
esac

echo ">> Stopping Odoo in the sibling container (${SIBLING})..."
SIB_ARGS=(--local)
[ -n "${ALL}" ] && SIB_ARGS+=(--all)
if ! "$(dirname "$0")/dexec.sh" "${SIBLING}" ./scripts/kill.sh "${SIB_ARGS[@]}"; then
  echo "!! Could not reach '${SIBLING}' — nothing stopped there (is it up?)" >&2
fi
