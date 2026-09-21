#!/usr/bin/env python3
"""Verify the reviewed offline notice inventory; makes no network requests."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'ThirdParty/Inventory.json').read_text())
for item in manifest['files']:
    path = root / item['path']
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != item['sha256']:
        raise SystemExit('Attribution inventory needs review: ' + item['path'])
notices = (root / 'ThirdParty/ThirdPartyNotices.txt').read_text()
for package in manifest['packages']:
    if not package['licenseFiles']:
        raise SystemExit('Missing license evidence: ' + package['name'])
    for name in package['licenseFiles']:
        if (root / name).read_text().strip() not in notices:
            raise SystemExit('License missing from shipped notices: ' + name)
print('PASS: runtime, pinned versions, license texts and shipped notices match the reviewed inventory')
