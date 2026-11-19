#!/usr/bin/env bash
# Shared helpers sourced by the other dev scripts.
# Do not execute directly.

# ---------------------------------------------------------------------------
# Config: each container sets ODOO_LOCAL_CONF to its own committed config
# (.devcontainer/odoo.{custom,client}.conf); that file becomes ODOO_RC for all
# script invocations. Override ODOO_LOCAL_CONF for one invocation to use a
# different conf (e.g. an alternate worktree/port) without touching the default.
# ---------------------------------------------------------------------------
_LOCAL_CONF="${ODOO_LOCAL_CONF:-/workspace/odoo.conf}"
if [ -f "${_LOCAL_CONF}" ]; then
  export ODOO_RC="${_LOCAL_CONF}"
fi
unset _LOCAL_CONF

# ---------------------------------------------------------------------------
# Addons path (escape hatch for one-off overrides)
# ---------------------------------------------------------------------------
# Preferred approach: set addons_path in the instance's conf file.
# EXTRA_ADDONS_PATHS (comma-separated) appends on top for quick experiments
# without touching the conf file.
ADDONS_PATH_ARG=()
if [ -n "${EXTRA_ADDONS_PATHS:-}" ]; then
  _conf="${ODOO_RC:-/workspace/.devcontainer/odoo.conf}"
  _base=$(grep '^addons_path' "${_conf}" | head -1 | sed 's/^addons_path[[:space:]]*=[[:space:]]*//' | tr -d ' ')
  ADDONS_PATH_ARG=(--addons-path "${_base},${EXTRA_ADDONS_PATHS}")
  unset _conf _base
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# setup_log <script-name> <db-name>
#   Creates /workspace/logs/<script-name>-<db-name>-<YYYYMMDD-HHMMSS>.log
#   and tees all subsequent stdout+stderr to it.
setup_log() {
  local script_name="$1" db_name="$2" ts log_dir
  ts=$(date +%Y%m%d-%H%M%S)
  log_dir="${LOGS_DIR:-/workspace/logs}"
  mkdir -p "${log_dir}"
  LOG_FILE="${log_dir}/${script_name}-${db_name}-${ts}.log"
  exec > >(tee -a "${LOG_FILE}") 2>&1
  echo ">> Log: ${LOG_FILE}"
}
