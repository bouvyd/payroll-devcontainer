# partena — Odoo dev container (multi-server)

This repo is a containerized Odoo development environment running **two** Odoo
instances that sync with each other, plus a shared Postgres:

- **`partena_custom`** — the CENTRAL / service-provider instance. Custom addons
  from `psbe-partena-20` (mounted at `src/partena-custom`). Serves **:8099**.
  VSCode attaches here by default, so you (Claude) normally run **inside** it.
- **`partena_client`** — a CUSTOMER instance that syncs to the central via an
  integration module. Custom addons from the same `psbe-partena-20` repo
  (mounted at `src/partena-custom`). Serves **:8089**. Runs as a peer container.

Both share the `db` Postgres and resolve each other by service name on the
`partena-net` network (e.g. `http://partena_custom:8099` from the client).

## Layout (inside the container)
- `/workspace` — this repo (scripts, devcontainer config, `.mcp.json`)
- `/workspace/src/odoo` — Odoo community (rw mount, branch master/20.0) — shared
- `/workspace/src/enterprise` — Odoo enterprise (rw mount) — shared
- `/workspace/src/design-themes` — design themes (rw mount) — shared
- `/workspace/src/partena-custom` — custom addons, `psbe-partena-20` (rw mount) — shared
- `/workspace/.odoo/{custom,client}` — per-instance filestore/sessions (persisted on host)
- Python venv: `/opt/venv` (on PATH). `odoo` wrapper → `odoo-bin`, config from
  `$ODOO_RC` — set per container to `.devcontainer/odoo.custom.conf` or
  `odoo.client.conf` (each pins that instance's addons_path, port, data_dir).

## Database
Postgres runs in the separate `db` service. From the container:
- CLI: `./scripts/dbsh.sh [dbname]` (or `psql -h db -U odoo ...`)
- MCP: the `postgres` server in `.mcp.json` is wired to `db:5432`.
- DO NOT USE THE `postgres` db for testing, etc. You can create new databases as you see fit. If you need to query and the MCP does not allow them, you can use the CLI.

## Running tests
```bash
./scripts/run-tests.sh <module>                 # fresh DB, install + run tests
./scripts/run-tests.sh <module> --test-tags /<module>
KEEP_DB=1 ./scripts/run-tests.sh <module>       # inspect the DB afterwards
```
A non-zero exit / `FAILED` lines in the log mean failing tests.

## Running the server
The scripts pick up the container's config automatically, and DB name defaults to
`$ODOO_DB` (the instance role). From the attached **central** container:
```bash
./scripts/init-db.sh partena_custom partena_custom   # one-time: create + install
./scripts/start.sh                                   # serve on http://localhost:8099
```
Each server has its own config (port, data_dir, `$ODOO_DB`), so client
operations must run **in** the `partena_client` container. From the attached `partena_custom` container you
drive it through `./scripts/dexec.sh` (uses the bind-mounted Docker socket — no
second terminal needed):
```bash
./scripts/dexec.sh partena_client ./scripts/init-db.sh partena_client <integration_module>
./scripts/dexec.sh partena_client ./scripts/start.sh          # serve on http://localhost:8089
./scripts/dexec.sh partena_client ./scripts/run-tests.sh <module>
./scripts/dexec.sh partena_client                            # drop into a shell
```
`dexec.sh <service> [cmd...]` runs any command in a sibling instance's container;
it works in both directions (e.g. from `partena_client`, target `partena_custom`).
This needs the Docker CLI + socket that the image/compose now provide — a change
to those requires an image rebuild.

## Stopping / wiping
```bash
./scripts/kill.sh          # stop the servers here AND in the sibling container
./scripts/kill.sh --local  # this container only
./scripts/kill.sh --all    # also kill a running run-tests.sh (skipped by default)
./scripts/clean.sh         # drop every DB (bar postgres/template*) + empty logs/
./scripts/clean.sh --force # ... disconnecting open sessions instead of failing
```
`clean.sh` asks for confirmation (`-y` to skip, required when not on a tty) and
takes `--dbs-only` / `--logs-only`. Postgres and `/workspace/logs` are shared by
both instances, so it wipes the client's databases too. Filestores under
`.odoo/{custom,client}` are left alone.

## Notes
- Python is 3.12; dependency pins come from `src/odoo/requirements.txt`, baked
  into the image. If those change, run `bin/sync-requirements.sh` on the host and
  rebuild the container.
- The container user (`odoo`, uid 1000) matches the host user, so files you
  create in the mounted repos stay host-owned.
- The `odoo` config is provided via `ODOO_RC` (not `-c`) so subcommands like
  `odoo shell` work. Barcode/raster rendering deps (`rlPyCairo`) are installed.

## Known quirk
- `base`'s `TestCommand.test_shell` fails *under the test runner* (it spawns a
  server subprocess through a pty; flaky regardless of this setup). `odoo shell`
  itself works fine. It never runs when you scope tests to a real module, so
  ignore it — don't treat it as an environment problem.
