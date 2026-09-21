#!/usr/bin/env python3
"""Query OSV using only public dependency names/versions and pinned Swift commits.
No source code, documents, credentials or local paths are sent. No installs occur.
"""
import argparse
import datetime
import json
from pathlib import Path
import urllib.request

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
inventory = json.loads((root / 'ThirdParty/Inventory.json').read_text())
provenance = json.loads((root / 'ThirdParty/Mermaid.json').read_text())
items = [{'name': 'mermaid', 'version': provenance['version']}] + inventory['packages']
queries = [{'package': {'name': p['name'], 'ecosystem': 'npm'}, 'version': p['version']} for p in items]
labels = [p['name'] + '@' + p['version'] for p in items]
for pin in json.loads((root / 'Package.resolved').read_text())['pins']:
    queries.append({'commit': pin['state']['revision']})
    labels.append(pin['identity'] + '@' + pin['state']['revision'])
request = urllib.request.Request('https://api.osv.dev/v1/querybatch', data=json.dumps({'queries': queries}).encode(), headers={'Content-Type': 'application/json'})
with urllib.request.urlopen(request, timeout=60) as response:
    result = json.load(response)
assert len(result['results']) == len(labels)
report = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'source': 'https://api.osv.dev/v1/querybatch', 'results': [{'dependency': name, **entry} for name, entry in zip(labels, result['results'])]}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n')
if any(entry.get('next_page_token') for entry in report['results']):
    raise SystemExit('Incomplete OSV results: pagination required; inspect the report before release.')
findings = [entry for entry in report['results'] if entry.get('vulns')]
for entry in findings:
    print(entry['dependency'], ', '.join(v['id'] for v in entry['vulns']))
print('Checked', len(labels), 'dependency versions/commits;', len(findings), 'with reported advisories. Review applicability; no match is not proof of safety.')
raise SystemExit(1 if findings else 0)
