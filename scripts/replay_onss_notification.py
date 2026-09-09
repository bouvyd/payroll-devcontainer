"""Replay an archived ONSS notification file from the central database.

Usage (from the partena_custom container):

    odoo shell -d <db> --no-http < scripts/replay_onss_notification.py

Set FILENAME to the l10n.be.onss.file record to replay, and flip APPLY / PUSH
to actually write and re-push. Everything is dry-run by default.
"""

FILENAME = "FO.NOTI.999999.20260806.00001.DIMN"
APPLY = False   # re-run _onss_apply_notification on the archived bytes
PUSH = False    # re-push the answered declarations to their customer database
COMMIT = False  # persist; otherwise the shell rolls back on exit

# The push matches on remote_ref. If the declaration was deleted and recreated in the
# customer database it carries a fresh uuid, so re-point the central record at it --
# {onss_ref: (new partena_dimona_ref, new remote id)} -- rather than letting the collect
# cron mint a second onss_ref the archived XML no longer names.
REBIND = {}

from odoo.addons.integration_onss.utils.dimn import DimnNotificationParser

Declaration = env["onss.dimona.declaration"].sudo()

onss_file = env["l10n.be.onss.file"].sudo().search([("name", "=", FILENAME)], limit=1)
assert onss_file, f"no archived file named {FILENAME}"
# Binary fields hand back a BinaryValue in 19.x -- .content is the raw bytes, no base64.
content = onss_file.file.content

parsed = DimnNotificationParser.parse(content)
print(f"{FILENAME}: {len(parsed)} form(s) -> {list(parsed)}")

matched = Declaration.browse()
for reference, result in parsed.items():
    declaration = Declaration.search([("onss_ref", "=", reference)], limit=1)
    print(f"\n{reference} -> {declaration.display_name if declaration else 'NO MATCH'}")
    print("  parsed now :", result["content"].get("declarationStatus"))
    print("  ticket     :", result["ticket"], "| provisional:", result["provisional"])
    if not declaration:
        continue
    matched |= declaration
    print("  stored     :", (declaration.response_content or {}).get("declarationStatus"))
    print("  state      :", declaration.state, "| remote_ref:", declaration.remote_ref)

for reference, (remote_ref, remote_id) in REBIND.items():
    declaration = Declaration.search([("onss_ref", "=", reference)], limit=1)
    declaration.write({"remote_ref": remote_ref, "id_remote_record": remote_id})
    print(f"\nrebound {reference} -> {remote_ref} (remote id {remote_id})")

if APPLY:
    connector = env["integration.connector"].sudo()._onss_connector()
    connector._onss_apply_notification(onss_file, content)
    print("\napplied:", [(d.onss_ref, d.state, d.result_state, d.result_code, d.result_provisional) for d in matched])

if PUSH:
    for project, declarations in matched.grouped("project_id").items():
        declarations._push_to_project(project)
        print(f"\npushed to {project.database_name}:")
        for declaration in declarations:
            print(f"  {declaration.onss_ref}: {declaration.state} {declaration.error_message or ''}")

if COMMIT:
    env.cr.commit()
    print("\ncommitted")
else:
    print("\ndry run -- nothing committed")
