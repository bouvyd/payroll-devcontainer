# partena

A self-contained, Docker-based Odoo development & test environment for the
Partena **client ↔ central** setup, designed so an agent (Claude Code) can build,
run and test both instances unattended. Tracks Odoo **master (20.0)**; the layout
is parametrized for other versions.

## What you get
Two networked Odoo instances (Python 3.12, Debian 12, wkhtmltopdf, all Odoo deps)
plus a shared Postgres — modeling a customer that syncs to a central provider:

- **`partena_custom`** — CENTRAL instance, custom addons from `psbe-partena-20`,
  serves **:8099**. VSCode attaches here (**Dev Containers: Reopen in Container**).
- **`partena_client`** — CUSTOMER instance, custom addons from the same
  `psbe-partena-20` repo (all modules live there for now), serves **:8089**.
  Runs as a peer container.
- A separate **`db`** Postgres container, networked to both (they resolve each
  other by service name on `partena-net`).
- Shared repos mounted **read-write**: `odoo`, `enterprise`, `design-themes`;
  both instances also mount the custom-addons repo (`psbe-partena-20`).
- Helper scripts to init DBs, run a server, run module tests headless, stop
  servers and wipe state.
- An optional host-side nginx config to reach both instances by hostname.
- A Postgres **MCP** server so Claude can query the DB; plus `psql` on the CLI.

## One-time setup
1. Install Docker + the VSCode **Dev Containers** extension.
2. Copy and edit env (lives next to the compose file):
   ```bash
   cp .devcontainer/.env.example .devcontainer/.env   # (already filled in for this machine)
   ```
   Set `USER_UID`/`USER_GID` (`id -u`, `id -g`), the shared repo paths
   (`ODOO_SRC`, `ENTERPRISE_SRC`, `DESIGN_THEMES_SRC`), and the custom
   repo (`PARTENA_CUSTOM_SRC` → your `psbe-partena-20` checkout; mounted in
   both instances, it holds both the central and the client modules).
3. Vendor Odoo's dependency list into the build context:
   ```bash
   ./bin/sync-requirements.sh
   ```
4. In VSCode: open this folder → **Dev Containers: Reopen in Container**.
   First build compiles Python deps (a few minutes), then `post-create.sh` runs.
5. Install the custom repo's git hooks (`pre-commit` is in the image; run it
   from inside the container so the hooks use the container's Python):
   ```bash
   cd /workspace/src/partena-custom && pre-commit install
   ```
   The hooks live in the repo's `.git/hooks`, so this is needed once per clone,
   not once per container rebuild.

## Daily use
The attached terminal is the **central** (`partena_custom`) container. Scripts
default the DB name to the instance role (`$ODOO_DB`):
```bash
./scripts/init-db.sh partena_custom partena_custom   # create + install central
./scripts/start.sh                                   # http://localhost:8099
./scripts/run-tests.sh <module>                      # fresh DB, install, run tests
./scripts/dbsh.sh partena_custom                     # psql shell
./scripts/kill.sh                                    # stop servers here + in the sibling
```
`run-tests.sh` serves its test run on port **8282** (container-internal, not
published), so tests can run while `start.sh` holds the instance's normal port.
Only one test run per container at a time, since they all use that port.

`kill.sh` leaves running test suites alone; `--local` limits it to this
container and `--all` also kills `run-tests.sh` runs.

Drive the **client** (`partena_client`) instance from the same terminal via
`dexec.sh` (it runs commands in the sibling container over the mounted Docker
socket) — or open a second terminal into it directly:
```bash
./scripts/dexec.sh partena_client ./scripts/init-db.sh partena_client <integration_module>
./scripts/dexec.sh partena_client ./scripts/start.sh   # http://localhost:8089
# equivalently, from the host:
#   docker compose -p partena exec partena_client bash
```

## Wiping everything
```bash
./scripts/clean.sh            # drop every DB (bar postgres/template*) + empty logs/
./scripts/clean.sh --force    # ... disconnecting open sessions instead of failing
```
It asks for confirmation (`-y` to skip) and takes `--dbs-only` / `--logs-only`.
Postgres and `logs/` are shared, so this wipes **both** instances' databases.
Filestores are left in place.

## Dropping a single database
Databases live in the shared `db` Postgres container; each also has a
filestore on disk under `.odoo/{custom,client}/filestore/<dbname>` that
`dropdb` does **not** clean up. From either container:
```bash
./scripts/dbsh.sh postgres -c "DROP DATABASE \"<dbname>\""
# or, if nothing is connected to it:
dropdb -h db -U odoo <dbname>

# then remove its filestore (path depends on which instance owns the DB):
rm -rf .odoo/custom/filestore/<dbname>    # central (partena_custom)
rm -rf .odoo/client/filestore/<dbname>    # customer (partena_client)
```
Never target the `postgres` maintenance database itself — see
[CLAUDE.md](CLAUDE.md).

## Ports & config
Each instance has its own committed config (`.devcontainer/odoo.{custom,client}.conf`)
pinning its `addons_path`, `http_port`/`gevent_port`, and `data_dir`
(`.odoo/{custom,client}`). Host ports come from `.env`
(`CUSTOM_HTTP_PORT`/`CLIENT_HTTP_PORT`, ...). To run several stacks side by side,
duplicate the checkout with a different `COMPOSE_PROJECT_NAME` and ports.

## Hostnames via nginx (optional, on the host)
[nginx/partena.dev.conf](nginx/partena.dev.conf) is a reverse proxy for the
host machine (not the containers) that serves the instances by name over
plain HTTP on port 80:

- `http://custom.partena.localhost` → central (`127.0.0.1:8099`)
- `http://client.partena.localhost` → customer (`127.0.0.1:8089`)

The names end in `.localhost` on purpose. Browsers treat `*.localhost` as a
secure context even over plain HTTP, so features that need one (clipboard,
service workers, `crypto.subtle`, ...) keep working. Browsers also resolve
`*.localhost` to loopback by themselves.

To set it up on your laptop:
1. (optional) Add the names to `/etc/hosts` (browsers don't need this, but `curl` and
   other non-browser tools may):
   ```
   127.0.0.1  client.partena.localhost custom.partena.localhost
   ```
2. Install the file so nginx includes it **inside the `http {}` block**
   (its directives fail at main-context level):
   - Debian/Ubuntu: `sudo cp nginx/partena.dev.conf /etc/nginx/conf.d/partena.conf`
   - macOS (brew): copy to `$(brew --prefix)/etc/nginx/servers/partena.conf`
   - Arch/CachyOS: the stock `nginx.conf` has no http-level include, so add one once:
     ```bash
     sudo mkdir -p /etc/nginx/conf.d
     sudo cp nginx/partena.dev.conf /etc/nginx/conf.d/partena.conf
     sudo sed -i '/^http {/a\    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
     ```
3. Check and reload: `sudo nginx -t && sudo systemctl reload nginx`.

The upstreams target the default host ports. If you changed `CUSTOM_HTTP_PORT` /
`CLIENT_HTTP_PORT` in `.env`, edit the `upstream` blocks to match. Session
cookies are not marked `secure` because the proxy serves plain HTTP; add TLS
before you set that flag.

See [CLAUDE.md](CLAUDE.md) for the in-container reference.
