#!/usr/bin/env python3
"""Capture public chapter fixtures for a rendering comparison; never used by the app."""
import json
from pathlib import Path
import re
import urllib.request
from urllib.parse import urljoin

root = Path(__file__).resolve().parents[1] / 'build/reader-fixture'
source = 'https://lotmreader.vercel.app'
root.mkdir(parents=True, exist_ok=True)
fixtures = {}
for slug in (1, 67):
    url = f'{source}/read/lotm/webnovel/{slug}'
    with urllib.request.urlopen(url, timeout=45) as response:
        page = response.read().decode()
    article = re.search(r'<article\b[^>]*class="[^"]*chapter-content[^>]*>([\s\S]*?)</article>', page).group(1)
    fixtures[str(slug)] = article
    if slug == 1:
        # Static SSR is enough for comparing chapter layout; avoid account/comment requests.
        page = re.sub(r'<script\b[^>]*>[\s\S]*?</script>', '', page)
        (root / 'baseline.html').write_text(page)
        for href in re.findall(r'<link[^>]*href="([^"]+\.css)"', page):
            path = urljoin(url, href).removeprefix(source).lstrip('/')
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(source + '/' + path, timeout=45) as response:
                target.write_bytes(response.read())
    for path in re.findall(r'<img\b[^>]*src="([^"]+)"', article):
        target = root / path.lstrip('/')
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(source + path, timeout=45) as response:
                target.write_bytes(response.read())
(root / 'chapters.json').write_text(json.dumps(fixtures, ensure_ascii=False))
print(f'Captured chapter HTML, online CSS, and illustrations in {root}')
