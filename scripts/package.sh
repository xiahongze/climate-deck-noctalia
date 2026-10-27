#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
tar -czf dist/climate-deck-noctalia.tar.gz catalog.toml climate-deck LICENSE
printf "%s\n" dist/climate-deck-noctalia.tar.gz
