#!/usr/bin/env bash
# refresh-agents.sh — regenerate scripts/lib/agents.json from the skills CLI.
#
# Run this after upgrading the `skills` npm package (or whenever new agents
# land upstream) to keep cortex's agent registry in sync.
#
#   bash scripts/refresh-agents.sh
#
# How it finds the skills source: looks at the most recently used npx cache
# entry containing `node_modules/skills/dist/cli.mjs`. If the cache is empty,
# warm it with `npx -y skills --version` first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
OUT="$LIB_DIR/agents.json"

command -v node >/dev/null 2>&1 || {
  echo "node not found. Install Node.js (https://nodejs.org) first." >&2
  exit 1
}

# Pick the newest cached skills package.
CLI_MJS="$(/bin/ls -t ~/.npm/_npx/*/node_modules/skills/dist/cli.mjs 2>/dev/null | head -1 || true)"
if [[ -z "$CLI_MJS" || ! -f "$CLI_MJS" ]]; then
  echo "couldn't find skills cli.mjs in ~/.npm/_npx/" >&2
  echo "warming the cache first…" >&2
  npx -y skills --version >/dev/null 2>&1 || true
  CLI_MJS="$(/bin/ls -t ~/.npm/_npx/*/node_modules/skills/dist/cli.mjs 2>/dev/null | head -1 || true)"
  [[ -f "$CLI_MJS" ]] || { echo "still not found — bailing" >&2; exit 1; }
fi

echo "source: $CLI_MJS"

tmp="$(mktemp)"
node "$LIB_DIR/extract-agents.mjs" "$CLI_MJS" > "$tmp"

# Sanity check: must be valid JSON and have at least 20 entries.
count="$(jq 'length' "$tmp" 2>/dev/null || echo 0)"
if ! [[ "$count" =~ ^[0-9]+$ ]] || (( count < 20 )); then
  echo "extracted only $count agents — refusing to overwrite $OUT" >&2
  rm -f "$tmp"
  exit 1
fi

mv "$tmp" "$OUT"
echo "✓ wrote $OUT ($count agents)"
