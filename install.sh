#!/usr/bin/env bash
# install.sh — add the `cortex` alias to your shell rc file.
#
#   bash install.sh
#
# Idempotent: safe to re-run. If an `alias cortex=` line already exists
# pointing somewhere else, the script reports the conflict and exits —
# it never overwrites an existing alias.
#
# After running, open a new terminal (or `source` the rc file) and try:
#   cortex --help

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORTEX_SH="$REPO_DIR/scripts/cortex.sh"

[[ -f "$CORTEX_SH" ]] || {
  echo "expected $CORTEX_SH to exist; aborting" >&2
  exit 1
}

# Pick the rc file from the login shell; fall back to whichever file exists.
case "$(basename "${SHELL:-}")" in
  zsh)  rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
  *)    if   [[ -f "$HOME/.zshrc"  ]]; then rc="$HOME/.zshrc"
        elif [[ -f "$HOME/.bashrc" ]]; then rc="$HOME/.bashrc"
        else
          echo "unknown shell ($SHELL) and neither ~/.zshrc nor ~/.bashrc exists." >&2
          echo "set the alias yourself:" >&2
          echo "  alias cortex=\"bash $CORTEX_SH\"" >&2
          exit 1
        fi
        ;;
esac

alias_line="alias cortex=\"bash $CORTEX_SH\""

# Already correct?
if grep -Fxq "$alias_line" "$rc" 2>/dev/null; then
  echo "✓ cortex alias already in $rc — nothing to do"
  exit 0
fi

# Conflicting alias?
if grep -Eq '^alias cortex=' "$rc" 2>/dev/null; then
  echo "⚠ an 'alias cortex=' line already exists in $rc but points elsewhere:" >&2
  echo "    current:  $(grep -E '^alias cortex=' "$rc")" >&2
  echo "    expected: $alias_line" >&2
  echo "  edit or remove the existing line and re-run." >&2
  exit 1
fi

# Append.
{
  printf '\n# cortex — added by install.sh\n'
  printf '%s\n' "$alias_line"
} >> "$rc"

echo "✓ added cortex alias to $rc"

# Non-blocking prereq check.
missing=()
command -v jq  >/dev/null 2>&1 || missing+=("jq")
command -v npx >/dev/null 2>&1 || missing+=("npx (install Node.js)")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo
  echo "  ⚠ missing prerequisites: ${missing[*]}"
  echo "    on macOS:  brew install jq node"
fi

echo
echo "  next: open a new terminal, or run"
echo "        source $rc"
echo "  then: cortex --help"
