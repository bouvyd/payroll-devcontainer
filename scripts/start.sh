#!/usr/bin/env bash
#
# Start the Odoo HTTP server (foreground) against a database.
# Uses the container's config (ODOO_RC): partena_custom serves on :8099,
# partena_client on :8089. DB defaults to $ODOO_DB (the container's role).
# Browse it from the host at http://localhost:<that port>.
#
# Usage:
#   ./scripts/start.sh [dbname] [extra odoo args]
#
# Env:
#   EXTRA_ADDONS_PATHS  comma-separated extra addon directories (see _common.sh)
set -euo pipefail
# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

DB="${1:-${ODOO_DB:-odoo}}"; shift || true

setup_log "start" "${DB}"

odoo -d "${DB}" --dev=reload,qweb,xml "${ADDONS_PATH_ARG[@]}" "$@"
