#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v noctalia >/dev/null || { echo "Noctalia 5 is required" >&2; exit 1; }
noctalia msg status >/dev/null || { echo "Start Noctalia first" >&2; exit 1; }
noctalia msg plugins source add climate-deck-local path "$repo_dir"
noctalia msg plugins enable xiahongze/climate-deck
printf "Climate Deck enabled. Open Settings → Plugins → Climate Deck to enter your tablet address.\n"
