# clodo

A self-contained, Docker-based Odoo development & test environment, designed so
an agent (Claude Code) can build, run and test Odoo unattended. Starts with
Odoo **19.0**; the layout is parametrized for other versions.

## What you get
Two networked Odoo instances (Python 3.12, Debian 12, wkhtmltopdf, all Odoo deps)
plus a shared Postgres — modeling a customer that syncs to a central provider:

- **`partena_custom`** — CENTRAL instance, custom addons from `psbe-partena-20`,
  serves **:8099**. VSCode attaches here (**Dev Containers: Reopen in Container**).
- **`partena_client`** — CUSTOMER instance, custom addons from
  `psbe-partena-standard`, serves **:8089**. Runs as a peer container.
- A separate **`db`** Postgres container, networked to both (they resolve each
  other by service name on `partena-net`).
- Shared repos mounted **read-write**: `odoo`, `enterprise`, `design-themes`;
  each instance additionally mounts its own custom-addons repo.
- Helper scripts to init DBs, run a server, and run module tests headless.
- A Postgres **MCP** server so Claude can query the DB; plus `psql` on the CLI.

## One-time setup
1. Install Docker + the VSCode **Dev Containers** extension.
2. Copy and edit env (lives next to the compose file):
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env   # (already filled in for this machine)
   ```
   Set `USER_UID`/`USER_GID` (`id -u`, `id -g`), the shared repo paths
   (`ODOO_SRC`, `ENTERPRISE_SRC`, `DESIGN_THEMES_SRC`), and the two custom
   repos (`PARTENA_STANDARD_SRC` → client, `PARTENA_CUSTOM_SRC` → central).
3. Vendor Odoo's dependency list into the build context:
   ```bash
   ./bin/sync-requirements.sh
   ```
4. In VSCode: open this folder → **Dev Containers: Reopen in Container**.
   First build compiles Python deps (a few minutes), then `post-create.sh` runs.

## Daily use
The attached terminal is the **central** (`partena_custom`) container. Scripts
default the DB name to the instance role (`$ODOO_DB`):
```bash
./scripts/init-db.sh partena_custom partena_custom   # create + install central
./scripts/start.sh                                   # http://localhost:8099
./scripts/run-tests.sh <module>                      # fresh DB, install, run tests
./scripts/dbsh.sh partena_custom                     # psql shell
```
For the **client** (`partena_client`) instance, open a second terminal into it:
```bash
docker compose -p partena exec partena_client bash
./scripts/init-db.sh partena_client <integration_module>
./scripts/start.sh                                   # http://localhost:8089
```

## Ports & config
Each instance has its own committed config (`.devcontainer/odoo.{custom,client}.conf`)
pinning its `addons_path`, `http_port`/`gevent_port`, and `data_dir`
(`.odoo/{custom,client}`). Host ports come from `.env`
(`CUSTOM_HTTP_PORT`/`CLIENT_HTTP_PORT`, ...). To run several stacks side by side,
duplicate the checkout with a different `COMPOSE_PROJECT_NAME` and ports.

See [CLAUDE.md](CLAUDE.md) for the in-container reference.
