# Community rules for Suricata

Chahã already uses `suricata-update` for Emerging Threats Open (ET Open). The Suricata role can add two optional rulesets to the same generated file. The sensor still sends Suricata alerts to Wazuh through `/var/log/suricata/eve.json`.

| Source | What it adds | Where it helps |
| --- | --- | --- |
| [julioliraup/Antiphishing](https://github.com/julioliraup/Antiphishing) (GPL-3.0) | DNS and TLS SNI domain lookups, an IPv4 destination lookup, and HTTP URL signatures. The reviewed revision contains 40,796 signatures, including three dataset rules. | SPAN traffic with visible DNS, TLS SNI or HTTP. The DNS rule needs visible queries from `HOME_NET`. Encrypted DNS and ECH can hide the relevant names, and a shared IP alert alone can be noisy. |
| [daffainfo/suricata-rules](https://github.com/daffainfo/suricata-rules) (Apache-2.0) | HTTP application rules covering common attack classes and product-specific signatures. The pilot includes 18 XSS and 23 SQL injection signatures. | Plain HTTP visible on the mirrored link, for example between a TLS-terminating proxy and a backend. Inspecting a mirrored HTTPS connection alone gives no HTTP request body or URI visibility. Measure overlap with ET Open before expanding the selection. |

## Deploy to the lab sensor

On the sensor, check `suricata -V` and `dpkg-query -W suricata-update`. Use an updater with the distro’s current security fixes. Ubuntu has [published fixes for unsafe rule archive handling](https://ubuntu.com/security/notices/USN-8766-1). The role expects the Ubuntu package layout and a working Suricata command socket for daily reloads. If you use a customized config, verify the active service points to `/etc/suricata/suricata.yaml` and that its rule files include the generated file.

```yaml
default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules
```

From the repository's `ansible` directory, test the sources one at a time against the ET Open baseline. Use a lab host in place of `sensor-01` if your inventory differs. The role validates the full configuration and restarts Suricata during a playbook run.

```bash
ansible-playbook suricata.yml --syntax-check
ansible-playbook suricata.yml --limit sensor-01 -e '{"suricata_antiphishing_enabled":true}'
ansible-playbook suricata.yml --limit sensor-01 -e '{"suricata_daffainfo_enabled":true}'
```

Keep the sources you choose in `group_vars/sensor_nodes.yml` or the lab host's variables so future runs use the same settings. For both sources, set:

```yaml
suricata_antiphishing_enabled: true
suricata_daffainfo_enabled: true
```

Antiphishing's [Linux wiki](https://github.com/julioliraup/Antiphishing/wiki/Configuration-Ruleset-on-GNU-Linux) uses the rolling indexed feed. This role instead downloads the rules and both datasets from one pinned revision, checks their SHA-256 values, and passes the local rule file to the existing updater. If you previously enabled the rolling source by hand, disable it with `sudo suricata-update disable-source julioliraup/antiphishing` before this pilot to avoid including the feed twice. Existing `suricata-update` filters and other configured sources still apply. With no enabled sources, the updater's default is ET Open.

## Verify the deployment

On the sensor:

```bash
sudo systemctl is-active suricata
sudo suricata -T --init-errors-fatal -c /etc/suricata/suricata.yaml
sudo suricatasc -c ruleset-stats
sudo suricatasc -c ruleset-reload-time
```

For Antiphishing, look for active SIDs `6000000`, `6000001`, and `6000002` in the merged file. These are DNS, TLS SNI, and IPv4 respectively. You can also verify a dataset is loaded without issuing a DNS request. Pass one base64-encoded entry from the deployed `phishing.lst` to `sudo suricatasc -c "dataset-lookup phishing_domains string $sample"`, where `sample` holds that encoded entry. For daffainfo, inspect the merged file for the SID prefixes `50100` (XSS) and `50300` (SQL injection).

To validate a representative signature, replay a lab PCAP offline. Use a DNS query from a source in `HOME_NET` for a domain from the staged dataset, or an existing lab PCAP that matches one of the selected HTTP signatures. Offline replay reads the packets from disk and sends no traffic. This command uses a separate EVE log and bypasses the live command socket.

```bash
replay_log=$(mktemp -d)
sudo suricata -c /etc/suricata/suricata.yaml --set unix-command.enabled=no \
  -r /path/to/lab.pcap -l "$replay_log"
sudo jq -c 'select(.event_type == "alert") | .alert' "$replay_log/eve.json"
```

For a Wazuh ingestion check, generate or replay the same benign fixture on an isolated lab segment that the SPAN port sees. Look for the SID first in EVE, then in the Chahã Suricata dashboard under `data.alert.signature_id`. Compare alert rates, repeated alerts, sensor RAM during reload, and capture drops against an equivalent ET Open baseline.

## Refresh or roll back

- At 05:00 sensor time, the existing root cron job calls `/usr/local/sbin/chaha-suricata-update`. It rebuilds and validates the merged rules, then uses the command socket to reload the running engine. Check `/var/log/suricata-update.log` after the first scheduled run. Allow memory headroom for the old and new detection engines to coexist during reload.
- The community revisions stay pinned across daily ET Open refreshes. For an Antiphishing refresh, update its commit and all three SHA-256 values together, then rerun Ansible. For daffainfo, review a new commit and adjust the optional `suricata_daffainfo_files` list before deployment. The role downloads rule data and does not execute upstream generators.
- To roll back a source, set its flag to `false` and rerun `suricata.yml` for the sensor. The generated file is rebuilt without that source, and future cron runs use the new selection. If the updater's configuration test fails, the updater restores any previous rules and the wrapper exits before restarting or reloading Suricata.

[Suricata rule loading](https://docs.suricata.io/en/suricata-7.0.11/configuration/suricata-yaml.html#rule-files) · [Suricata dataset commands](https://docs.suricata.io/en/suricata-7.0.3/rules/datasets.html) · [Rule reloads](https://docs.suricata.io/en/suricata-7.0.15/rule-management/rule-reload.html)
