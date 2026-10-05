#!/usr/bin/env python3
"""Bounded retention for a single-node Wazuh 4.x AIO. Standard library only."""
import argparse
import base64
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import ssl
import time
import urllib.request

INDEX = re.compile(r'^wazuh-(alerts|archives)-4\.x-(\d{4}\.\d{2}\.\d{2})$')
ROTATED = re.compile(r'^ossec-(archive|alerts)-\d{2}(?:-\d+)?\.(json|log)\.gz$')

def emit(event, **fields):
    print(json.dumps(dict(event=event, **fields)), flush=True)

def usage(path):
    s = os.statvfs(path)
    # Include ext4 reserved blocks as unavailable to ingestion services.
    return 100 * (1 - s.f_bavail / s.f_blocks)

def open_inodes():
    opened = set()
    for proc in Path('/proc').glob('[0-9]*/fd'):
        try:
            for fd in proc.iterdir():
                try:
                    s = fd.stat()
                    opened.add((s.st_dev, s.st_ino))
                except FileNotFoundError:
                    pass
        except FileNotFoundError:
            pass
    return opened

def local_candidates(root, days, now, opened):
    cutoff = now - days * 86400
    result = []
    root = Path(root)
    for p in root.glob('*/*/*'):
        if not ROTATED.fullmatch(p.name) or p.is_symlink() or not p.is_file():
            continue
        if p.resolve().parent.parent.parent != root.resolve():
            continue
        s = p.stat()
        if s.st_mtime < cutoff and (s.st_dev, s.st_ino) not in opened:
            result.append((s.st_mtime, p))
    return [p for _, p in sorted(result)]

def eligible_index(name, created_ms, days, now):
    m = INDEX.fullmatch(name)
    if not m:
        return False
    try:
        date = dt.datetime.strptime(m[2], '%Y.%m.%d').replace(tzinfo=dt.timezone.utc)
        # Protect both recently created/reindexed indices and recent event dates.
        end = date.timestamp() + 86400
        return max(end, int(created_ms) / 1000) < now - days * 86400
    except (ValueError, TypeError):
        return False

class API:
    def __init__(self, c):
        self.c = c
        self.ctx = ssl.create_default_context(cafile=c['ca'])
    def request(self, path, method='GET'):
        c = self.c
        if not c['url'].startswith('https://'):
            raise ValueError('HTTPS required')
        req = urllib.request.Request(c['url'].rstrip('/') + path, method=method)
        auth = base64.b64encode((c['username'] + ':' + c['password']).encode()).decode()
        req.add_header('Authorization', 'Basic ' + auth)
        with urllib.request.urlopen(req, context=self.ctx, timeout=20) as r:
            return json.load(r)

def run(c, dry):
    now = time.time()
    for normal, floor in [('archive_days', 'archive_min_days'), ('alert_days', 'alert_min_days'), ('index_days', 'index_min_days')]:
        if not 1 <= c[floor] <= c[normal]:
            raise ValueError('Invalid retention range: ' + normal)
    if not 0 < c['target'] < c['trigger'] < 95:
        raise ValueError('Invalid disk thresholds')
    roots = [('archives', c['archive_days'], c['archive_min_days']), ('alerts', c['alert_days'], c['alert_min_days'])]
    pressure = {os.stat(p).st_dev: p for p in [c['log_root'], c['index_path']]}
    initial = {dev: usage(p) for dev, p in pressure.items()}
    triggered = {dev for dev, u in initial.items() if u >= c['trigger']}
    def needs(dev):
        return dev in triggered and usage(pressure[dev]) > c['target']
    for emergency in [False, True]:
        opened = open_inodes()
        for kind, normal, floor in roots:
            root = Path(c['log_root']) / kind
            dev = root.stat().st_dev
            for p in local_candidates(root, floor if emergency else normal, now, opened):
                if emergency and not needs(dev):
                    break
                # Recheck immediately before unlink, including current open files.
                s = p.stat()
                if (s.st_dev, s.st_ino) in open_inodes():
                    continue
                emit('would_delete_file' if dry else 'delete_file', path=str(p), bytes=s.st_size, emergency=emergency)
                if not dry:
                    p.unlink()
                    checksum = p.with_suffix('.sum')
                    if checksum.is_file() and not checksum.is_symlink():
                        checksum.unlink()
    index_error = False
    try:
        api = API(c['indexer'])
        # Refuse index deletion on multi-node clusters: this role is AIO-only.
        if api.request('/_cluster/health')['number_of_data_nodes'] != 1:
            raise RuntimeError('Indexer is not single-node')
        indices = api.request('/wazuh-alerts-4.x-*,wazuh-archives-4.x-*/_settings?allow_no_indices=true&ignore_unavailable=true&flat_settings=true')
        aliases = api.request('/_alias')
        dev = os.stat(c['index_path']).st_dev
        for emergency in [False, True]:
            for name, data in sorted(list(indices.items())):
                if emergency and not needs(dev):
                    break
                # Conservatively preserve any aliased index (including write aliases).
                if aliases.get(name, {}).get('aliases'):
                    continue
                days = (c['archive_min_days'] if emergency else c['archive_days']) if name.startswith('wazuh-archives-') else (c['index_min_days'] if emergency else c['index_days'])
                if not eligible_index(name, data['settings'].get('index.creation_date'), days, now):
                    continue
                # Recheck aliases immediately before deletion.
                if api.request('/' + name + '/_alias').get(name, {}).get('aliases'):
                    continue
                emit('would_delete_index' if dry else 'delete_index', index=name, emergency=emergency)
                if not dry:
                    result = api.request('/' + name, 'DELETE')
                    if not result.get('acknowledged'):
                        raise RuntimeError('Index deletion not acknowledged')
                    del indices[name]
                    time.sleep(2)
    except Exception as e:
        # Never log credentials or HTTP response bodies.
        emit('index_cleanup_failed', error=type(e).__name__)
        index_error = True
    final = {str(p): round(usage(p), 2) for p in pressure.values()}
    unresolved = any(needs(dev) for dev in pressure)
    emit('finished', dry_run=dry, disk_used_percent=final, target_unmet=unresolved)
    return 1 if index_error or (unresolved and not dry) else 0

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', default='/etc/wazuh-storage.json')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    with open('/run/wazuh-storage.lock', 'w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(0)
        with open(args.config) as f:
            config = json.load(f)
        raise SystemExit(run(config, args.dry_run))
