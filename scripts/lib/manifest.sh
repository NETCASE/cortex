# lib/manifest.sh — cortex manifest read/write.
#
# Sourced by scripts/cortex.sh. Does not run standalone.
#
# Manifest locations:
#   global  → ~/.cortex/manifest.json
#   project → <cwd>/.cortex.json    (per project directory)
#
# Exposes:
#   GLOBAL_MANIFEST          — absolute path of the global manifest
#   project_manifest_for <d> — manifest path for a given project root
#   manifest_path_for <s>    — global|project → corresponding manifest path
#   manifest_init <path>     — create empty {version:1,skills:{}} if absent
#   manifest_upsert ...      — write/refresh one skill entry (see below)
#   read_manifest <path>     — emit `.skills` object (or {} if missing)

GLOBAL_MANIFEST="$HOME/.cortex/manifest.json"

project_manifest_for() { echo "$1/.cortex.json"; }

manifest_path_for() {
  case "$1" in
    global)  echo "$GLOBAL_MANIFEST" ;;
    project) echo "$PWD/.cortex.json" ;;
  esac
}

manifest_init() {
  local path="$1"
  [[ -f "$path" ]] && return
  mkdir -p "$(dirname "$path")"
  echo '{"version":1,"skills":{}}' > "$path"
}

# manifest_upsert <path> <name> <provider> <source> <scope> <profile> \
#                 <agents_json> [<universal_agents_json>] [<universal_more>]
#
# Write-once invariant: `first_seen` captures when cortex first saw the skill
# and never changes on later runs. Implementation: the `//` fallback supplies
# a default object containing first_seen only when the entry is absent; the
# trailing `+` merge overwrites every other field. `del(.adopted)` strips the
# legacy field from old manifests.
#
# universal_agents / universal_more are only written when this run captured
# them. Re-runs that didn't see an "Installation Summary" block (e.g. an
# already-installed source) preserve the previously recorded values.
manifest_upsert() {
  local path="$1" name="$2" provider="$3" source="$4" scope="$5" prof="$6"
  local agents="$7" universal_agents="${8:-[]}" universal_more="${9:-0}"
  local now tmp
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq --arg name "$name" \
     --arg provider "$provider" \
     --arg source "$source" \
     --arg scope "$scope" \
     --arg prof "$prof" \
     --argjson agents "$agents" \
     --argjson universal_agents "$universal_agents" \
     --argjson universal_more "$universal_more" \
     --arg now "$now" '
     .skills[$name] = (
       (.skills[$name] // { first_seen: $now })
       + { provider: $provider, source: $source, scope: $scope, profile: $prof,
           agents: $agents, updated_at: $now }
       + (if ($universal_agents | length) > 0
          then { universal_agents: $universal_agents }
          else {} end)
       + (if $universal_more > 0
          then { universal_more: $universal_more }
          else {} end)
       | del(.adopted)
     )
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
}

# Read manifest at $1 (defaults to {} if missing). Emits the .skills object.
read_manifest() {
  local path="$1"
  if [[ -f "$path" ]]; then jq -c '.skills // {}' "$path"; else echo '{}'; fi
}
