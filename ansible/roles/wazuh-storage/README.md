# Wazuh AIO storage protection

A Python standard-library service runs five minutes after boot and five minutes
following each completion. Installed automatically by `site.yml` and
`wazuh-aio.yml`, or independently with `wazuh-storage.yml` on inventory group `aio`.
Only single-node Wazuh 4.x indexers are supported.

## Install on an existing server

From the repository's `ansible` directory:

```bash
ansible-playbook wazuh-storage.yml --limit Wazuh-AIO
```

Replace `Wazuh-AIO` with your actual inventory host, or omit `--limit` to target
all members of `aio`. The timer is enabled on deployment and deletes eligible
history on its first run. Back up any history that must be preserved elsewhere.

The role uses the repository's `indexer_admin_password` by default. Set the real
password through Ansible Vault; do not commit it. Prefer a dedicated cleanup
account via `wazuh_storage_indexer_username/password` with cluster health, index
settings/alias read access and delete access limited to the two event families.
No account is created by this role. The default admin account is compatible with
the existing installation but has broader permissions than cleanup requires.

HTTPS certificate validation is mandatory. Override `wazuh_storage_indexer_url`
with the certificate's DNS name/IP if its SAN does not cover 127.0.0.1, and set
`wazuh_storage_indexer_ca` if your CA path differs. Indexer API failure is reported
as service failure; local-file cleanup is still performed first.

## Policy

| Data | Normal age | Emergency minimum |
|---|---:|---:|
| Rotated raw archives / indexed raw archives | 7 days | 2 days |
| Rotated local alerts | 14 days | 7 days |
| Indexed alerts | 30 days | 7 days |

Normal expiration runs every invocation. At >=80% usage, additional local
archives, local alerts, then event indices may be deleted until usage reaches
70%. Minimum ages are hard stops. Filesystem usage includes ext4 reserved space.
Each cleanup targets its own filesystem. Edit `ansible/group_vars/aio.yml` for deployment settings. It overrides role defaults automatically.

This service implements index age retention directly through the API; it does
not also install ISM policies. Existing ISM policies are not modified and may
independently delete data sooner. Inspect those before relying on minimum ages.

Files must match dated Wazuh rotated gzip paths. Their age is measured from
mtime; active top-level files, symlinks and open files are excluded. Matching
`.json.sum`/`.log.sum` checksums are removed with the archive. Local retention does
not verify Filebeat delivery: it also bounds available replay history.

Only exact daily `wazuh-alerts-4.x-YYYY.MM.DD` and
`wazuh-archives-4.x-YYYY.MM.DD` indices qualify. Both creation time and the end of
the named event day must be older than retention. Any aliased index is preserved.
No indexer database files, inventory indices or system indices are removed.

Journald gets a 200M target and 2G free-space preference. Other application logs
remain under their existing rotation configuration; they are not deleted by this
role. The earlier `/etc/cron.daily/wazuh-archive-retention` is removed.

## Operate and inspect

```bash
sudo /usr/local/sbin/wazuh-storage --dry-run
sudo systemctl list-timers wazuh-storage.timer
sudo systemctl start wazuh-storage.service
sudo journalctl -u wazuh-storage.service -n 100 --no-pager
```

Dry run performs reads and prints candidates, without deleting. It cannot model
actual reclaimed space, so emergency output lists all eligible candidates while
usage remains high. Stop the timer if inspecting before the next scheduled run:

```bash
sudo systemctl stop wazuh-storage.timer
sudo /usr/local/sbin/wazuh-storage --dry-run
sudo systemctl start wazuh-storage.timer
```

Logs are JSON lines. Index API errors or inability to reach the target result in
nonzero exit status. Wire service failures into your external monitoring: this
role does not send email/webhook alerts or verify ingestion freshness. Minimum
retention, active files, or unrelated disk usage can prevent recovery; this is not
a guarantee against disk exhaustion. Timeout is 15 minutes; remaining work is
retried next run. No automatic service restarts or write-block changes are made.

## Validation

```bash
python3 -m unittest discover -s roles/wazuh-storage/tests -v
ansible-playbook wazuh-storage.yml --syntax-check
```

Test on a disposable AIO before production: exercise retention, 80% pressure,
API failure, protected history exhaustion, and Ansible rerun idempotency. Unit
tests cover candidate safety; no live Wazuh deletion was tested during authoring.

## Centralized configuration

Edit `ansible/group_vars/aio.yml` to change retention, thresholds, the timer
interval, indexer connection, paths, or journal size. Ansible automatically
loads it for the `aio` group in all three playbooks; no `vars_files` or
`include_vars` is needed. Role defaults remain fallback values for reuse.

After changes, rerun `ansible-playbook wazuh-storage.yml` from `ansible/`.
Retention and threshold changes are read on the next service run; interval
changes reload the timer and journal changes restart journald. Existing
`group_vars/all.yml` and `group_vars/sensor_nodes.yml` need no changes.
If you already have an `aio.yml`, merge these settings into it.
