#!/usr/bin/env bash
# cortex — CLI for the NETCASE skills repo.
#
# Usage:
#   cortex install [-v] [<profile>]   install all sources in profiles/<profile>.json
#                                      (no <profile> → pick from a list;
#                                       -v / --verbose → stream skills.sh output live)
#   cortex status                list installed skills (BY: cortex / ext)
#   cortex detect-agents         agents auto-detect would target
#   cortex update                update all installed skills   (coming soon)
#   cortex remove                remove installed skills        (coming soon)
#   cortex --help
#
# Architecture: this is the single entry point. Worker code lives in lib/.
# See ARCHITECTURE.md for the code map and design notes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILES_DIR="$REPO_ROOT/profiles"
LIB_DIR="$SCRIPT_DIR/lib"

. "$LIB_DIR/style.sh"
. "$LIB_DIR/manifest.sh"
. "$LIB_DIR/source.sh"

# ── shared helpers ───────────────────────────────────────────────
list_profiles() {
  ls "$PROFILES_DIR"/*.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.json$//'
}

need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "cortex needs 'jq' — install with: brew install jq" >&2
    exit 1
  }
}

need_npx() {
  command -v npx >/dev/null 2>&1 || {
    echo "cortex needs 'npx' — install Node.js (https://nodejs.org) first." >&2
    exit 1
  }
}

usage() {
  print_header "help"
  cat <<EOF
  cortex — NETCASE skills CLI

    cortex install [-v] [<profile>]  install all sources from profiles/<profile>.json
                                     (-v / --verbose → stream skills.sh output live)
    cortex status                    list installed skills (global, then folder),
                                     with BY column: cortex / universal / ext
    cortex detect-agents         show which agents auto-detect would target
    cortex update                update all installed skills        (coming soon)
    cortex remove                remove installed skills            (coming soon)
    cortex --help

  Available profiles: $(list_profiles | paste -sd' ' -)
EOF
  print_footer
}

# ── install ──────────────────────────────────────────────────────
pick_profile() {
  # Prints the chosen profile name to stdout; menu + prompt go to stderr.
  local profiles=() p i=1 choice
  while IFS= read -r p; do profiles+=("$p"); done < <(list_profiles)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    echo "No profiles found in $PROFILES_DIR" >&2
    exit 1
  fi
  echo "Available profiles:" >&2
  for p in "${profiles[@]}"; do
    printf "  %d) %s\n" "$i" "$p" >&2
    i=$((i + 1))
  done
  printf "Pick a profile [1-%d] (q to quit): " "${#profiles[@]}" >&2
  read -r choice || exit 0
  [[ "$choice" =~ ^[qQ]$ || -z "$choice" ]] && exit 0
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#profiles[@]} )); then
    echo "Invalid choice: $choice" >&2
    exit 1
  fi
  echo "${profiles[$((choice - 1))]}"
}

# install_one_source <src_json> <profile_name> <verbose:0|1>
#
# Process one entry from a profile's `sources` array. Resolves the source,
# determines the authoritative skill list (explicit `skills` array or
# `skills add --list`), runs the install, parses the captured output for
# universal-agent info, then writes a manifest entry for every name the
# post-install snapshot confirms.
#
# verbose=0: skills.sh output is hidden; cortex prints a compact summary.
# verbose=1: skills.sh output is streamed live (same as the captured copy).
# In either mode, a non-zero exit from `skills add` dumps the captured
# output to stderr so the user can see what went wrong.
install_one_source() {
  local src="$1" profile="$2" verbose="${3:-0}"
  local scope provider source_str resolved_line
  local skills_json agents_json scope_flag
  local after manifest captured exit_code
  local skill_args agent_args desc tracked names_to_track
  local name actual_agents
  local parsed_universal universal_csv universal_more universal_agents_json
  local installed_names all_symlink all_universal max_universal_more

  scope="$(jq -r '.scope // "global"' <<<"$src")"
  case "$scope" in
    global|project) ;;
    *) echo "  ! Unknown scope '$scope' — skipping: $src" >&2; return ;;
  esac

  resolved_line="$(resolve_source "$src")" || return
  provider="${resolved_line%%	*}"
  source_str="${resolved_line#*	}"

  skills_json="$(jq -c '.skills // []' <<<"$src")"
  agents_json="$(jq -c '.agents // []' <<<"$src")"

  scope_flag=""
  [[ "$scope" == "global" ]] && scope_flag="-g"

  # Build skill / agent CLI arg arrays. `--skill` and `-a` are variadic in
  # the skills CLI → put `--skill` LAST so it can't swallow other flags;
  # `-a` must come BEFORE `--skill` so it stops at the boundary.
  skill_args=()
  agent_args=()
  if [[ "$(jq 'length' <<<"$skills_json")" -gt 0 ]]; then
    skill_args=(--skill)
    while IFS= read -r s; do skill_args+=("$s"); done < <(jq -r '.[]' <<<"$skills_json")
  fi
  if [[ "$(jq 'length' <<<"$agents_json")" -gt 0 ]]; then
    agent_args=(-a)
    while IFS= read -r a; do agent_args+=("$a"); done < <(jq -r '.[]' <<<"$agents_json")
  elif [[ -n "${CORTEX_AGENTS:-}" ]]; then
    agent_args=(-a)
    IFS=',' read -ra _a <<<"$CORTEX_AGENTS"
    for a in "${_a[@]}"; do agent_args+=("$a"); done
  fi

  desc=" [$provider]"
  [[ ${#skill_args[@]} -gt 0 ]] && desc+=" [skills: $(jq -r 'join(", ")' <<<"$skills_json")]"
  if [[ ${#agent_args[@]} -gt 0 ]]; then
    if [[ "$(jq 'length' <<<"$agents_json")" -gt 0 ]]; then
      desc+=" [agents: $(jq -r 'join(", ")' <<<"$agents_json")]"
    else
      desc+=" [agents: ${CORTEX_AGENTS}]"
    fi
  fi
  echo "→ $source_str ($scope)$desc"

  # Decide which skill names belong to this source. Explicit `skills` array
  # wins; otherwise ask `skills add --list`. Empty result → warn and skip
  # manifest tracking (we'd rather under-record than write phantom entries).
  names_to_track=()
  if [[ "$(jq 'length' <<<"$skills_json")" -gt 0 ]]; then
    while IFS= read -r n; do names_to_track+=("$n"); done < <(jq -r '.[]' <<<"$skills_json")
  else
    while IFS= read -r n; do
      [[ -n "$n" ]] && names_to_track+=("$n")
    done < <(list_source_skills "$source_str")
    if [[ ${#names_to_track[@]} -eq 0 ]]; then
      echo "  ! could not list skills for $source_str — install proceeding without manifest tracking" >&2
    fi
  fi

  # Run the install. Capture stdout+stderr to a temp file. In verbose mode
  # also tee to the terminal for live progress.
  captured="$(mktemp)"
  if [[ "$verbose" == 1 ]]; then
    npx -y skills add "$source_str" $scope_flag -y \
      ${agent_args[@]+"${agent_args[@]}"} \
      ${skill_args[@]+"${skill_args[@]}"} </dev/null 2>&1 | tee "$captured"
    exit_code=${PIPESTATUS[0]}
  else
    npx -y skills add "$source_str" $scope_flag -y \
      ${agent_args[@]+"${agent_args[@]}"} \
      ${skill_args[@]+"${skill_args[@]}"} </dev/null >"$captured" 2>&1
    exit_code=$?
  fi

  if [[ $exit_code -ne 0 ]]; then
    echo "  ✗ skills add failed (exit $exit_code) — full output:" >&2
    cat "$captured" >&2
    rm -f "$captured"
    return
  fi

  after="$(snapshot_for_scope "$scope")"

  # Parse universal-agent info out of the captured Installation Summary block.
  # parsed_universal becomes { "<skill>": { universal_csv, universal_more } }.
  parsed_universal="$(parse_install_capture "$captured" | jq -Rs '
    split("\n") | map(select(length > 0)) | map(split("\t")) |
    map({ key: .[0], value: { csv: .[1], more: (.[2] | tonumber) } }) |
    from_entries
  ')"

  manifest="$(manifest_path_for "$scope")"
  manifest_init "$manifest"

  # Accumulators for the compact summary line.
  installed_names=()
  all_symlink='[]'
  all_universal='[]'
  max_universal_more=0

  tracked=0
  for name in "${names_to_track[@]}"; do
    [[ -z "$name" ]] && continue
    actual_agents="$(jq -c --arg n "$name" \
      'map(select(.name == $n)) | (.[0].agents // [])' <<<"$after")"
    if [[ -z "$actual_agents" || "$actual_agents" == "null" ]] || \
       [[ "$(jq --arg n "$name" 'any(.name == $n)' <<<"$after")" != "true" ]]; then
      continue
    fi

    universal_csv="$(jq -r --arg n "$name" '.[$n].csv // ""' <<<"$parsed_universal")"
    universal_more="$(jq -r --arg n "$name" '.[$n].more // 0' <<<"$parsed_universal")"
    if [[ -n "$universal_csv" ]]; then
      universal_agents_json="$(jq -Rc 'split(", ")' <<<"$universal_csv")"
    else
      universal_agents_json='[]'
    fi

    manifest_upsert "$manifest" "$name" "$provider" "$source_str" "$scope" "$profile" \
      "$actual_agents" "$universal_agents_json" "$universal_more"
    tracked=$((tracked + 1))
    installed_names+=("$name")

    all_symlink="$(jq -c --argjson new "$actual_agents" '. + $new | unique' <<<"$all_symlink")"
    all_universal="$(jq -c --argjson new "$universal_agents_json" '. + $new | unique' <<<"$all_universal")"
    if [[ "$universal_more" -gt "$max_universal_more" ]]; then
      max_universal_more=$universal_more
    fi
  done

  # Compact summary (non-verbose only — in verbose the full CLI output is
  # already on screen).
  if [[ "$verbose" != 1 && $tracked -gt 0 ]]; then
    local skills_csv sym_csv uni_csv line
    skills_csv="$(IFS=,; printf '%s' "${installed_names[*]}" | sed 's/,/, /g')"
    sym_csv="$(jq -r 'join(", ")' <<<"$all_symlink")"
    uni_csv="$(jq -r 'join(", ")' <<<"$all_universal")"
    echo "  ✓ installed $tracked skill(s): $skills_csv"
    line=""
    [[ -n "$sym_csv" ]] && line+="symlink: $sym_csv"
    if [[ -n "$uni_csv" || $max_universal_more -gt 0 ]]; then
      [[ -n "$line" ]] && line+=" · "
      line+="universal: $uni_csv"
      [[ $max_universal_more -gt 0 ]] && line+=" (+$max_universal_more more)"
    fi
    [[ -n "$line" ]] && echo "    $line"
  fi

  echo "  tracked $tracked skill(s) in $(echo "$manifest" | sed "s|^$HOME|~|")"
  echo
  rm -f "$captured"
}

cmd_install() {
  need_jq
  need_npx

  # Argument parsing: -v / --verbose accepted anywhere before the profile name.
  local verbose=0
  local positional=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose) verbose=1; shift ;;
      --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done ;;
      -*) echo "unknown flag: $1  (use -v / --verbose)" >&2; exit 1 ;;
      *) positional+=("$1"); shift ;;
    esac
  done

  print_header "install"
  local profile="${positional[0]:-}"
  if [[ -z "$profile" ]]; then
    profile="$(pick_profile)"
  fi
  local profile_file="$PROFILES_DIR/$profile.json"
  if [[ ! -f "$profile_file" ]]; then
    echo "no such profile: $profile  (have: $(list_profiles | paste -sd' ' -))" >&2
    exit 1
  fi
  jq -e . "$profile_file" >/dev/null || {
    echo "Invalid JSON in $profile_file" >&2
    exit 1
  }

  echo "Installing skills from profile: $profile$([[ $verbose == 1 ]] && echo "  (verbose)")"
  echo "Source: $profile_file"
  echo

  local count=0
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    install_one_source "$src" "$profile" "$verbose"
    count=$((count + 1))
  done < <(jq -c '.sources[]' "$profile_file")

  if [[ $count -eq 0 ]]; then
    echo "No sources in profile '$profile'."
  else
    echo "✓ Processed $count source(s) from profile '$profile'."
    echo "  Run 'cortex status' to see installed skills."
  fi

  print_footer
}

# ── status ───────────────────────────────────────────────────────

# Display-name → home-relative dir for the per-agent symlink locations.
AGENT_LINK_DIRS='{
  "Claude Code": ".claude",
  "Qwen Code": ".qwen",
  "Continue": ".continue",
  "Cursor": ".cursor",
  "Gemini CLI": ".gemini",
  "Codex": ".codex",
  "Windsurf": ".windsurf",
  "OpenCode": ".config/opencode",
  "Goose": ".config/goose",
  "GitHub Copilot": ".config/github-copilot",
  "Amp": ".amp",
  "Cline": ".cline",
  "Roo Code": ".roo",
  "Kilo Code": ".kilo",
  "Junie": ".junie",
  "Kiro": ".kiro"
}'

print_global() {
  local json manifest
  json="$(npx -y skills list --global --json 2>/dev/null || echo '[]')"
  if [[ "$(echo "$json" | jq 'length')" -eq 0 ]]; then echo "  $DIM(none)$RESET"; return; fi
  manifest="$(read_manifest "$GLOBAL_MANIFEST")"
  {
    printf 'NAME\tBY\tAGENT\tPATH\n'
    # One row per (skill, agent). PATH is the agent's symlink path; falls back
    # to the canonical store path when the agent's dir isn't in AGENT_LINK_DIRS.
    # BY column: cortex / ext, computed against the global manifest.
    echo "$json" | jq -r \
      --argjson m "$AGENT_LINK_DIRS" \
      --arg home "$HOME" \
      --argjson mani "$manifest" '
      .[] | . as $s |
      ($s.agents // []) as $ags |
      ($mani[$s.name].universal_agents // []) as $ugs |
      ($mani[$s.name].universal_more // 0) as $umore |
      (if $mani[$s.name] then "cortex" else "ext" end) as $by |
      (
        # Symlink rows (one per agent in `agents`, or a placeholder if empty).
        if ($ags | length) == 0
        then [ $s.name, $by, "—", ($s.path | sub("^"+$home; "~")) ]
        else $ags[] | [ $s.name, $by, .,
                        (if $m[.] then "~/" + $m[.] + "/skills/" + $s.name
                         else ($s.path | sub("^"+$home; "~")) end) ]
        end
      ),
      # Universal rows: one per named universal agent.
      ($ugs[] | [ $s.name, "universal", ., "~/.agents/skills/" + $s.name ]),
      # "+N more" row for unnamed universal agents.
      (if $umore > 0
       then [ $s.name, "universal", "(+\($umore) more)", "" ]
       else empty
       end)
      | @tsv'
  } | fmt_table | style_name_column | style_by_column
}

# Project skills, grouped by the folder that contains them. Excludes the
# canonical store (~/.agents/skills/) and per-agent dirs (~/.<agent>/skills/),
# which belong to the "Globally installed" section.
print_folders() {
  local json rows
  json="$(npx -y skills list --json 2>/dev/null || echo '[]')"
  rows="$(echo "$json" | jq -r --arg home "$HOME" '
    .[]
    | (.path | ltrimstr($home + "/")) as $rest
    | select(($rest | test("^\\.[^/]+/skills/")) | not)
    | select(.path | test("/(?:\\.claude/)?skills/[^/]+$"))
    | (.path | capture("(?<root>.*?)/(?<rel>(?:\\.claude/)?skills/[^/]+)$")) as $m
    | [ $m.root,
        .name,
        ( if ((.agents // []) | length) == 0 then "—" else (.agents | join(", ")) end ),
        $m.rel ] | @tsv' 2>/dev/null)"
  if [[ -z "$rows" ]]; then echo "  $DIM(none)$RESET"; return; fi

  local roots root first=1 short name manifest
  roots="$(printf '%s\n' "$rows" | cut -f1 | sort -u)"
  while IFS= read -r root; do
    [[ -z "$root" ]] && continue
    [[ $first -eq 0 ]] && echo
    first=0
    short="${root/#$HOME/~}"
    name="$(basename "$root")"
    manifest="$(read_manifest "$(project_manifest_for "$root")")"
    printf '  %s▸%s %s%s%s  %s%s%s\n\n' "$TEAL" "$RESET" "$BOLD" "$name" "$RESET" "$DIM" "$short" "$RESET"
    {
      printf 'NAME\tBY\tAGENTS\tPATH\n'
      printf '%s\n' "$rows" \
        | awk -F'\t' -v r="$root" 'BEGIN{OFS="\t"} $1==r { print $2,$3,$4 }' \
        | jq -Rr --argjson mani "$manifest" 'split("\t") as $r |
            ( if $mani[$r[0]] then "cortex" else "ext" end ) as $by |
            [ $r[0], $by, $r[1], $r[2] ] | @tsv'
    } | fmt_table | style_name_column | style_by_column
  done <<<"$roots"
}

cmd_status() {
  need_jq
  print_header "status"
  printf '  %sGlobally installed skills%s  %s~/.agents/skills/%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET"
  print_global
  echo
  printf '  %sFolder-local skills%s\n\n' "$BOLD" "$RESET"
  print_folders
  print_footer
}

# ── detect-agents ────────────────────────────────────────────────
# Known agent-id → home-relative directory. skills.sh auto-detects an agent
# when its directory exists; this map mirrors that for the common ones.
AGENT_DIRS="claude-code:.claude
qwen-code:.qwen
continue:.continue
cursor:.cursor
gemini-cli:.gemini
codex:.codex
windsurf:.windsurf
github-copilot:.config/github-copilot
opencode:.config/opencode
goose:.config/goose
amp:.amp
cline:.cline
roo:.roo
kilo:.kilo
kode:.kode
codebuddy:.codebuddy
trae:.trae
warp:.warp
junie:.junie
firebender:.firebender
aider-desk:.aider-desk
crush:.crush
mux:.mux
openhands:.openhands
kimi-cli:.kimi"

cmd_detect_agents() {
  print_header "detect-agents"
  printf '  %sAgents whose directory exists under your home — `cortex install` targets all of these:%s\n\n' "$DIM" "$RESET"

  local rows="" id dir
  while IFS=: read -r id dir; do
    [[ -d "$HOME/$dir" ]] && rows+="$id"$'\t'"~/$dir"$'\n'
  done <<<"$AGENT_DIRS"

  if [[ -z "$rows" ]]; then
    echo "  $DIM(none detected)$RESET"
  else
    { printf 'AGENT\tDIRECTORY\n'; printf '%s' "$rows"; } | fmt_table | style_name_column
  fi

  echo
  printf '  %sNote: this mirrors the skills.sh directory-presence heuristic. A few agents are\n' "$DIM"
  printf '  detected via editor plugins or other markers this scan does not check (e.g. some\n'
  printf '  GitHub Copilot setups) — those still get installed by `cortex install`. To target\n'
  printf '  a specific agent only:  npx skills add <repo> -a <agent-id>%s\n' "$RESET"
  print_footer
}

# ── placeholders ─────────────────────────────────────────────────
cmd_update() {
  print_header "update"
  printf '  %snot yet implemented%s\n' "$DIM" "$RESET"
  print_footer
}

cmd_remove() {
  print_header "remove"
  printf '  %snot yet implemented%s\n' "$DIM" "$RESET"
  print_footer
}

# ── dispatch ─────────────────────────────────────────────────────
case "${1:-}" in
  install)        shift; cmd_install "$@" ;;
  status)         cmd_status ;;
  detect-agents)  cmd_detect_agents ;;
  update)         cmd_update ;;
  remove)         cmd_remove ;;
  ""|--help|-h)   usage ;;
  *)
    echo "unknown command: $1" >&2
    echo >&2
    usage >&2
    exit 1 ;;
esac
