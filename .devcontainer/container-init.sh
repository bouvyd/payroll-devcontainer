#!/usr/bin/env bash
# Each Odoo service's `command`. Runs on every `up`, in BOTH containers (unlike
# the devcontainer postCreateCommand, which only runs in the attached one), so
# the peer container self-provisions its Python deps too. Then idles — servers
# are started on demand via ./scripts/start.sh.
set -euo pipefail

# Separate filestores/sessions for the two servers (shared /workspace mount).
mkdir -p /workspace/.odoo/client /workspace/.odoo/custom

# Install the mounted custom repo's Python requirements. Only one of these is
# mounted per container; the other path simply won't exist.
for repo in partena-standard partena-custom; do
  req="/workspace/src/${repo}/requirements.txt"
  if [ -f "${req}" ]; then
    echo ">> Installing requirements for ${repo}: ${req}"
    pip install -q -r "${req}" || echo "!! Failed to install ${req} (continuing)" >&2
  fi
done

exec sleep infinity
