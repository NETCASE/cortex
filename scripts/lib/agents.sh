# lib/agents.sh — agent registry helpers.
#
# Sourced by scripts/cortex.sh. Does not run standalone.
#
# The registry itself lives in scripts/lib/agents.json, generated from
# skills.sh source by `scripts/refresh-agents.sh`. Each entry has:
#   { "name", "displayName", "skillsDir", "isUniversal", "homeDir" }
#
# Exposes:
#   AGENTS_JSON_PATH                 — absolute path to agents.json
#   agents_all_json                  — full registry as JSON array
#   agents_installed_json            — JSON array of currently installed agents
#                                      (detection mirrors skills.sh:detectInstalled)
#   agent_lookup <name> <field>      — print one field of a single agent, or empty

AGENTS_JSON_PATH="$LIB_DIR/agents.json"

agents_all_json() {
  if [[ -f "$AGENTS_JSON_PATH" ]]; then
    cat "$AGENTS_JSON_PATH"
  else
    echo '[]'
  fi
}

# Look up one field of one agent by name.
#   agent_lookup claude-code displayName  → "Claude Code"
#   agent_lookup amp isUniversal          → "true"
#   agent_lookup nonexistent foo          → "" (exit 0)
agent_lookup() {
  local name="$1" field="$2"
  jq -r --arg n "$name" --arg f "$field" \
    'map(select(.name == $n)) | .[0][$f] // ""' "$AGENTS_JSON_PATH" 2>/dev/null
}

# Emit installed agents — names only, one per line. Detection mirrors
# skills.sh:detectInstalled — a single `existsSync` against each agent's
# representative home directory.
agents_installed_names() {
  while IFS=$'\t' read -r name home_dir; do
    [[ -z "$name" || -z "$home_dir" ]] && continue
    [[ -e "$HOME/$home_dir" ]] && printf '%s\n' "$name"
  done < <(jq -r '.[] | [.name, .homeDir] | @tsv' "$AGENTS_JSON_PATH" 2>/dev/null)
}

# Same, but as a JSON array.
agents_installed_json() {
  local names
  names="$(agents_installed_names)"
  if [[ -z "$names" ]]; then
    echo '[]'
  else
    jq -Rsc 'split("\n") | map(select(length > 0))' <<<"$names"
  fi
}
