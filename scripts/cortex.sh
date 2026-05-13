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
. "$LIB_DIR/agents.sh"

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
# `skills add --list`), runs the install, then writes a manifest entry for
# every name the post-install snapshot confirms.
#
# verbose=0: skills.sh output is hidden; cortex prints a compact summary.
# verbose=1: skills.sh output is streamed live via `tee`.
# In either mode, a non-zero exit from `skills add` dumps the captured
# output to stderr so the user can see what went wrong.
install_one_source() {
  local src="$1" profile="$2" verbose="${3:-0}"
  local scope provider source_str resolved_line
  local skills_json agents_json scope_flag
  local after manifest captured exit_code
  local skill_args agent_args desc tracked names_to_track
  local name actual_agents
  local installed_names all_symlink

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
  # wins; otherwise ask `skills add --list`.
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

  # Run install. Capture to a temp file; tee live in verbose mode.
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
  manifest="$(manifest_path_for "$scope")"
  manifest_init "$manifest"

  installed_names=()
  all_symlink='[]'

  tracked=0
  for name in "${names_to_track[@]}"; do
    [[ -z "$name" ]] && continue
    actual_agents="$(jq -c --arg n "$name" \
      'map(select(.name == $n)) | (.[0].agents // [])' <<<"$after")"
    if [[ -z "$actual_agents" || "$actual_agents" == "null" ]] || \
       [[ "$(jq --arg n "$name" 'any(.name == $n)' <<<"$after")" != "true" ]]; then
      continue
    fi
    manifest_upsert "$manifest" "$name" "$provider" "$source_str" "$scope" "$profile" "$actual_agents"
    tracked=$((tracked + 1))
    installed_names+=("$name")
    all_symlink="$(jq -c --argjson new "$actual_agents" '. + $new | unique' <<<"$all_symlink")"
  done

  # Compact summary (default mode only). Universal agents come from the
  # registry — every installed universal-mode agent on the machine sees
  # any skill cortex writes to ~/.agents/skills/.
  if [[ "$verbose" != 1 && $tracked -gt 0 ]]; then
    local skills_csv sym_csv uni_csv line
    local installed_universal_names
    skills_csv="$(IFS=,; printf '%s' "${installed_names[*]}" | sed 's/,/, /g')"
    sym_csv="$(jq -r 'join(", ")' <<<"$all_symlink")"
    if [[ "$scope" == "global" ]]; then
      installed_universal_names="$(
        agents_all_json | jq -r --argjson installed "$(agents_installed_json)" '
          map(select(.isUniversal and (.name as $n | $installed | index($n)))) |
          map(.displayName) | sort | join(", ")
        '
      )"
      uni_csv="$installed_universal_names"
    else
      uni_csv=""
    fi
    echo "  ✓ installed $tracked skill(s): $skills_csv"
    line=""
    [[ -n "$sym_csv" ]] && line+="symlink: $sym_csv"
    if [[ -n "$uni_csv" ]]; then
      [[ -n "$line" ]] && line+=" · "
      line+="universal: $uni_csv"
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
    # Display-name → { skillsDir, isUniversal } from the registry. Used both
    # to render the per-agent path for symlink rows and to know which agents
    # are universal-mode.
    local display_info installed_universal_names
    display_info="$(
      agents_all_json | jq -c '
        map({ key: .displayName, value: { skillsDir, isUniversal } }) | from_entries
      '
    )"
    # Names of installed universal agents (by displayName) — these are the
    # ones we expand as extra rows under each managed skill.
    installed_universal_names="$(
      agents_all_json | jq -c --argjson installed "$(agents_installed_json)" '
        map(select(.isUniversal and (.name as $n | $installed | index($n)))) |
        map(.displayName)
      '
    )"

    echo "$json" | jq -r \
      --arg home "$HOME" \
      --argjson mani "$manifest" \
      --argjson info "$display_info" \
      --argjson universals "$installed_universal_names" '
      .[] | . as $s |
      ($s.agents // []) as $ags |
      (if $mani[$s.name] then "cortex" else "ext" end) as $by |
      (
        # Per-agent symlink rows. Path comes from the registry: skillsDir
        # gives ".claude/skills" → "~/.claude/skills/<name>". Universal-mode
        # agents share the canonical store path ("~/.agents/skills/<name>").
        # Unknown agents (not in registry) fall back to $s.path.
        if ($ags | length) == 0
        then [ $s.name, $by, "—", ($s.path | sub("^"+$home; "~")) ]
        else $ags[] | . as $ag |
                      [ $s.name, $by, $ag,
                        (if $info[$ag] then "~/" + $info[$ag].skillsDir + "/" + $s.name
                         else ($s.path | sub("^"+$home; "~")) end) ]
        end
      ),
      # Universal rows: one per detected universal agent, but only for
      # cortex-managed skills (ext skills get no expansion).
      (if $by == "cortex"
       then $universals[] | . as $ag |
            select(($ags | index($ag)) | not) |
            [ $s.name, "universal", $ag, "~/.agents/skills/" + $s.name ]
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

cmd_detect_agents() {
  need_jq
  print_header "detect-agents"
  printf '  %sAgents skills.sh would auto-detect on this machine — `cortex install` targets all of these:%s\n\n' "$DIM" "$RESET"

  # Walk the registry, emit one row per agent whose home dir exists.
  local rows="" name display home_dir is_universal kind
  while IFS=$'\t' read -r name display home_dir is_universal; do
    [[ -z "$name" || -z "$home_dir" ]] && continue
    [[ -e "$HOME/$home_dir" ]] || continue
    kind="symlink"
    [[ "$is_universal" == "true" ]] && kind="universal"
    rows+="$display"$'\t'"$name"$'\t'"$kind"$'\t'"~/$home_dir"$'\n'
  done < <(jq -r '.[] | [.name, .displayName, .homeDir, .isUniversal] | @tsv' "$AGENTS_JSON_PATH")

  if [[ -z "$rows" ]]; then
    echo "  $DIM(none detected)$RESET"
  else
    { printf 'AGENT\tID\tKIND\tHOME\n'; printf '%s' "$rows"; } | fmt_table | style_name_column
  fi

  echo
  printf '  %sRegistry: %s agent(s) total, sourced from skills.sh.\n' "$DIM" "$(jq 'length' "$AGENTS_JSON_PATH")"
  printf '  Refresh with: bash scripts/refresh-agents.sh.\n'
  printf '  To target a specific agent only:  npx skills add <repo> -a <id>%s\n' "$RESET"
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
