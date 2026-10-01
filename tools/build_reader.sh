#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -d node_modules ]; then npm ci; fi
node node_modules/vite/bin/vite.js build --config reader/vite.config.ts
mkdir -p assets/fonts
cp reader/source/fonts/* assets/fonts/
cp reader/source/lib/meta.json assets/meta.json
cp LICENSE.md assets/license.md
