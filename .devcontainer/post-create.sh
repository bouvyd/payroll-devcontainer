#!/usr/bin/env bash
# Runs once, inside the ATTACHED container (partena_custom by default), right
# after it is created. Per-container dependency install + data dirs are handled
# by container-init.sh (it runs in both containers on every `up`); this script
# just does friendly sanity checks and hints for the interactive session.
set -euo pipefail

echo ">> Preparing Odoo dev container..."

# Data dir for filestore/sessions (bind-mounted to the host workspace).
mkdir -p /workspace/.odoo/client /workspace/.odoo/custom

# Sanity-check the mounted source repos. The shared ones are in every container;
# the custom repo differs per instance (only one is mounted here).
for repo in odoo enterprise design-themes; do
  if [ ! -d "/workspace/src/${repo}" ] || [ -z "$(ls -A "/workspace/src/${repo}" 2>/dev/null)" ]; then
    echo "!! WARNING: /workspace/src/${repo} is empty — check the path in .env" >&2
  fi
done
if [ ! -d /workspace/src/partena-custom ]; then
  echo "!! WARNING: no partena custom repo mounted — check PARTENA_CUSTOM_SRC in .env" >&2
fi

echo ">> Odoo version: $(odoo --version 2>/dev/null || echo '??')"
cat <<'EOF'
>> Done. Two Odoo instances share the `db` service:
     partena_custom (central) -> ./scripts/start.sh   # http://localhost:8099
     partena_client (customer): docker compose -p partena exec partena_client bash
                                then ./scripts/start.sh # http://localhost:8089
   On the compose network they reach each other as partena_client / partena_custom.
EOF
