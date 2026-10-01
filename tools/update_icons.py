#!/usr/bin/env python3
"""Refresh the vendored Iconify glyphs used by the shared reader (build time only)."""
import collections
import concurrent.futures
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
groups = collections.defaultdict(set)
groups['material-symbols'].update(f'format-align-{align}' for align in ('left', 'center', 'right', 'justify'))
sources = list((ROOT / 'reader/source/lib/reader').glob('*.svelte'))
for path in sources:
    for collection, name in re.findall(r'["\']([a-z0-9-]+):([a-z0-9-]+)["\']', path.read_text()):
        if collection in {'og', 'twitter'}:
            continue
        groups[collection].add(name)

def fetch(item):
    collection, names = item
    url = f'https://api.iconify.design/{collection}.json?icons=' + ','.join(sorted(names))
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            data = json.load(response)
    except urllib.error.HTTPError:
        # Some networks block Iconify's API. The maintained icon-set repository is equivalent.
        with urllib.request.urlopen(f'https://raw.githubusercontent.com/iconify/icon-sets/master/json/{collection}.json', timeout=60) as response:
            data = json.load(response)
    icons = {}
    for name in names:
        icon = dict(data['icons'].get(name, {}))
        if not icon:
            alias = data.get('aliases', {}).get(name)
            if alias:
                icon = {**data['icons'][alias['parent']], **alias}
        if not icon:
            print(f'Source website references unavailable glyph: {collection}:{name}')
            continue
        icons[f'{collection}:{name}'] = {'body': icon['body'], 'width': icon.get('width', data.get('width', 16)), 'height': icon.get('height', data.get('height', 16))}
    return icons

icons = {}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    for result in pool.map(fetch, groups.items()):
        icons.update(result)
target = ROOT / 'reader/icons.json'
target.write_text(json.dumps(icons, ensure_ascii=False, sort_keys=True, indent=2) + '\n')
print(f'Vendored {len(icons)} reader icons in {target}')
