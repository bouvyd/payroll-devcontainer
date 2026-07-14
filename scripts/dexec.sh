#!/usr/bin/env bash
#
# Run a command inside a SIBLING instance's container, from within another one.
# Uses the host Docker socket (bind-mounted by docker-compose.yml). This is how
# an agent attached to partena_custom drives the partena_client instance (and
# vice versa): init/install/update a DB, start the server, tail logs, etc.
#
# Usage:
#   ./scripts/dexec.sh <service> [cmd...]      # default cmd: interactive shell
#
# Examples (run from the partena_custom container):
#   ./scripts/dexec.sh partena_client ./scripts/init-db.sh partena_client <module>
#   ./scripts/dexec.sh partena_client ./scripts/start.sh          # serve :8089
#   ./scripts/dexec.sh partena_client ./scripts/run-tests.sh <module>
#   ./scripts/dexec.sh partena_client                             # drop into a shell
#
# The target container already carries its own env (ODOO_RC, ODOO_DB, venv on
# PATH), so the scripts behave exactly as they do when run there directly.
set -euo pipefail

SERVICE="${1:?usage: dexec.sh <service> [cmd...]}"; shift || true

# docker needs to reach the socket; the image grants odoo passwordless sudo, so
# fall back to it when the socket isn't group-accessible to the odoo user.
DOCKER=(docker)
if ! docker version >/dev/null 2>&1; then
  DOCKER=(sudo docker)
fi

# Resolve the sibling's container id by its compose service label (no dependency
# on container_name or the project name).
CID="$("${DOCKER[@]}" ps -q -f "label=com.docker.compose.service=${SERVICE}" -f "status=running" | head -n1)"
if [ -z "${CID}" ]; then
  echo "!! No running container found for compose service '${SERVICE}'." >&2
  echo "   Is the stack up? Try:  ${DOCKER[*]} ps" >&2
  exit 1
fi

# Allocate a TTY only when we actually have one (keeps it usable from agents).
TTY_FLAGS=(-i)
[ -t 0 ] && TTY_FLAGS+=(-t)

# Default to a login shell (loads venv PATH); passed commands inherit the
# container's env PATH (venv is baked in) and run from /workspace.
if [ "$#" -eq 0 ]; then
  set -- bash -l
fi

exec "${DOCKER[@]}" exec "${TTY_FLAGS[@]}" -w /workspace "${CID}" "$@"
