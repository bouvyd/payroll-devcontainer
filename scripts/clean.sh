#!/usr/bin/env bash
#
# Wipe the dev environment's state: drop every database on the shared `db`
# service (except postgres/template0/template1) and delete the script logs.
#
# DESTRUCTIVE and shared: both instances use the same Postgres and the same
# /workspace/logs, so this wipes the client's databases as well as the
# central's. It asks for confirmation unless -y is given.
#
# A database with open connections cannot be dropped: stop the servers first
# (./scripts/kill.sh) or pass --force to disconnect their backends.
#
# Usage:
#   ./scripts/clean.sh                # confirm, then drop DBs + remove logs
#   ./scripts/clean.sh -y             # no confirmation
#   ./scripts/clean.sh --force        # kick open connections before dropping
#   ./scripts/clean.sh --dbs-only     # keep the logs
#   ./scripts/clean.sh --logs-only    # keep the databases
#
# Filestores under .odoo/{custom,client}/filestore are left in place; they are
# harmless leftovers, and `rm -rf` on them is not something to do implicitly.
set -euo pipefail
# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

YES=""
FORCE=""
DO_DBS=1
DO_LOGS=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     YES=1 ;;
    -f|--force)   FORCE=1 ;;
    --dbs-only)   DO_LOGS="" ;;
    --logs-only)  DO_DBS="" ;;
    -h|--help)    awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *) echo "!! Unknown argument '$1' (see --help)" >&2; exit 2 ;;
  esac
  shift
done

LOG_DIR="${LOGS_DIR:-/workspace/logs}"
PSQL=(psql -h "${PGHOST:-db}" -U "${PGUSER:-odoo}" -d postgres -tAq)

DBS=""
if [ -n "${DO_DBS}" ]; then
  DBS=$("${PSQL[@]}" -c \
    "SELECT datname FROM pg_database
      WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname")
fi

# --- what is about to go ----------------------------------------------------
echo "== Databases to drop =="
if [ -z "${DO_DBS}" ]; then
  echo "(skipped: --logs-only)"
elif [ -z "${DBS}" ]; then
  echo "(none)"
else
  while read -r db; do
    conns=$("${PSQL[@]}" -c \
      "SELECT count(*) FROM pg_stat_activity WHERE datname = '${db}'")
    if [ "${conns}" -gt 0 ]; then
      echo "  ${db}  (${conns} open connection(s)$([ -n "${FORCE}" ] && echo ", will be disconnected"))"
    else
      echo "  ${db}"
    fi
  done <<< "${DBS}"
fi

echo "== Logs to delete =="
if [ -z "${DO_LOGS}" ]; then
  echo "(skipped: --dbs-only)"
elif [ -d "${LOG_DIR}" ]; then
  count=$(find "${LOG_DIR}" -type f | wc -l)
  size=$(du -sh "${LOG_DIR}" | cut -f1)
  echo "  ${LOG_DIR}: ${count} file(s), ${size}"
else
  echo "(none: ${LOG_DIR} does not exist)"
fi

if [ -z "${YES}" ]; then
  if [ ! -t 0 ]; then
    echo "!! Not a terminal and -y not given; aborting." >&2
    exit 1
  fi
  read -r -p "Proceed? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) echo ">> Aborted."; exit 1 ;;
  esac
fi

# --- drop ------------------------------------------------------------------
failed=""
if [ -n "${DO_DBS}" ] && [ -n "${DBS}" ]; then
  while read -r db; do
    if [ -n "${FORCE}" ]; then
      "${PSQL[@]}" -c \
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
          WHERE datname = '${db}' AND pid <> pg_backend_pid()" >/dev/null
    fi
    if dropdb -h "${PGHOST:-db}" -U "${PGUSER:-odoo}" --if-exists "${db}" 2>/dev/null; then
      echo ">> Dropped '${db}'"
    else
      echo "!! Could not drop '${db}' (in use?)" >&2
      failed+=" ${db}"
    fi
  done <<< "${DBS}"
fi

# --- logs ------------------------------------------------------------------
if [ -n "${DO_LOGS}" ] && [ -d "${LOG_DIR}" ]; then
  find "${LOG_DIR}" -mindepth 1 -delete
  echo ">> Emptied ${LOG_DIR}"
fi

if [ -n "${failed}" ]; then
  echo "!! Still there:${failed}" >&2
  echo "   Stop the servers (./scripts/kill.sh) or re-run with --force." >&2
  exit 1
fi
echo ">> Clean."
