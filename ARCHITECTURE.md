# Architecture

This document is the entry point for contributors — human or AI — who
need to read, change, or extend cortex. End-user docs live in
[README.md](README.md).

Read top to bottom on a first pass. Sections 1–3 build the mental model;
4 is the code walkthrough; 5–8 are reference material.

---

## 1 · Mental model

cortex is a profile-replay layer on top of the [skills.sh
CLI](https://skills.sh). The skills CLI installs and lists individual
skills; cortex describes a *machine setup* as a JSON file you can
re-apply anywhere, and records the result so you can later tell what
it manages from what the user installed by hand.

### The state we care about

There are three pieces of state, in three places:

```
┌──────────────────┐        ┌─────────────────────┐        ┌────────────────┐
│  profile (json)  │ ─────▶ │  on-disk skills     │ ─────▶ │  manifest      │
│  (versioned,     │        │  (where skills.sh   │        │  (what cortex │
│   intent)        │        │   put them)         │        │   thinks it    │
│                  │        │                     │        │   manages)     │
└──────────────────┘        └─────────────────────┘        └────────────────┘
        ▲                            ▲                             ▲
        │ user edits                 │ `skills add` writes         │ cortex writes
        │                            │   (or removes)              │   after each install
```

A skill's "BY" state in `cortex status` is the join of the **on-disk
skills** with the **manifest**:

| On disk? | In manifest? | BY |
|---|---|---|
| yes | yes | `cortex` — the skill belongs to a source in some profile, and cortex is tracking it |
| yes | no  | `ext` — present on disk, unknown to cortex (manual `npx skills add`, leftover from another tool, …) |
| no  | yes | orphan in the manifest (future `cortex remove --prune` will clean these) |
| no  | no  | — |

The manifest is a strict mirror of "what is referenced by some profile
and made it onto disk". A skill that's *referenced* in a profile but
that the install failed to put on disk is **not** in the manifest. A
skill that's *on disk* but not referenced by any profile is **not**
in the manifest, even if cortex saw it before.

### Lifecycle of a skill

```
        not in profile, not on disk
                  │
                  │ user adds source to profile and runs cortex install
                  ▼
        ┌────────────────────┐
        │   cortex          │  ← in profile, on disk, in manifest
        │                    │
        └────────────────────┘
            ▲             │
            │             │ user removes source from profile,
   cortex  │             │ runs cortex install (future --prune)
   install  │             ▼
            │     orphan in manifest
            │     (will be cleaned by --prune)
            │
        manually installed
        (on disk, not in profile, not in manifest = ext)
```

A skill never "remembers" that it was installed outside cortex — once
it's referenced by a profile and the install succeeds, it's `cortex`,
full stop. If the user removes the source from the profile later, the
manifest entry becomes an orphan and the skill goes back to `ext`.

---

## 2 · Components

```
cortex/
├── install.sh                  ← one-shot installer that registers the `cortex` alias
├── scripts/
│   ├── cortex.sh              ← single entry point; the `cortex` alias points here
│   ├── refresh-agents.sh      ← regenerates lib/agents.json from skills.sh source
│   └── lib/
│       ├── style.sh           ← ANSI colours, banner, table formatters
│       ├── manifest.sh        ← manifest paths + read/write/upsert
│       ├── source.sh          ← provider detection + skills.sh snapshots
│       ├── agents.sh          ← agent registry helpers (read agents.json)
│       ├── agents.json        ← embedded copy of the skills.sh agent registry
│       └── extract-agents.mjs ← Node parser invoked by refresh-agents.sh
├── profiles/<name>.json       ← versioned profile files
├── skills/<name>/             ← published NETCASE skills (independent of the CLI)
├── README.md                  ← end-user docs
└── ARCHITECTURE.md            ← this file
```

`cortex.sh` is the only entry point. The libs are pure source files —
they contain no top-level code, only function definitions. Sourcing one
in isolation (`. scripts/lib/source.sh`) gives you its helpers in your
shell, which is handy for poking at `resolve_source` while developing.

### What lives where

| File | Lines | Owns |
|---|---|---|
| `scripts/cortex.sh` | ~430 | Dispatcher and `cmd_*` functions, including the install loop. |
| `scripts/lib/style.sh` | ~145 | All colour / banner / table primitives. The only file that reads `NO_COLOR`. |
| `scripts/lib/manifest.sh` | ~70 | Manifest I/O. The only file that writes to `~/.cortex/` or `<cwd>/.cortex.json`. |
| `scripts/lib/source.sh` | ~80 | `resolve_source` and snapshot helpers. The only file that calls `npx skills list` / `skills add --list`. |
| `scripts/lib/agents.sh` | ~50 | Reads `agents.json`, exposes detected/installed/lookup helpers. |
| `scripts/lib/agents.json` | (data) | Embedded snapshot of skills.sh's agent registry — name, displayName, skillsDir, isUniversal, homeDir. |
| `scripts/lib/extract-agents.mjs` | ~75 | Node parser; reads skills.sh `cli.mjs` and writes `agents.json`. Run via `scripts/refresh-agents.sh`. |

The "only file that does X" property is intentional — it means a change
to manifest format, or a new provider, has one place to touch.

---

## 3 · Walkthrough: what happens during `cortex install system`

This is the most useful read on a first contact: trace one command end-to-end.

1. **Dispatch** ([cortex.sh:456-468](scripts/cortex.sh#L456-L468)). The
   `case` on `${1:-}` matches `install`, shifts, calls `cmd_install`
   with the rest of the args.

2. **`cmd_install`** ([cortex.sh:247-297](scripts/cortex.sh#L247-L297)).
   - `need_jq` / `need_npx` — abort early if missing.
   - `print_header "install"` — banner.
   - Resolve the profile name (or `pick_profile` interactively).
   - `jq -e .` against `profiles/<profile>.json` — fail fast on bad JSON.
   - Loop over each element of `.sources[]`, calling `install_one_source`.

3. **`install_one_source`** ([cortex.sh:102-245](scripts/cortex.sh#L102-L245)). For each entry:
   - **Validate scope** (global / project / else skip).
   - **`resolve_source`** ([lib/source.sh:resolve_source](scripts/lib/source.sh#L16-L58)) — pattern-match the `source` string to `(provider, resolved_path_or_url)`. See §6.1.
   - **Build CLI args**. `--skill` and `-a` are variadic in the skills
     CLI, so order matters: `-a …` first, `--skill …` last.
   - **Decide which names belong to this source** (§6.2): explicit
     `skills` list wins; otherwise `list_source_skills` asks
     `skills add --list` and parses the output.
   - **`npx skills add <resolved> [-g] [-y] [-a …] [--skill …]`**. We
     redirect stdin from `</dev/null` so `npx` doesn't read the profile
     file (npm is quirky when stdin is a TTY-less file).
   - **`snapshot_for_scope` (after)** — JSON array of skills the CLI
     reports for this scope after the install.
   - **`manifest_upsert`** ([lib/manifest.sh:manifest_upsert](scripts/lib/manifest.sh#L44-L64))
     for every expected name that the post-install snapshot confirms.
     Names not in `after` are dropped (the install failed for them).

4. **Footer**. `print_footer` writes the version / size / date line.

That's the entire install path. About 300 lines of bash, end to end.

---

## 4 · `cortex status` walkthrough

1. **`cmd_status`** ([cortex.sh:401-410](scripts/cortex.sh#L401-L410)).
   Calls `print_global` and `print_folders`.

2. **`print_global`** ([cortex.sh:301-360](scripts/cortex.sh#L301-L360)).
   - `npx skills list --global --json` — every globally installed skill,
     each with its `agents` list.
   - `read_manifest "$GLOBAL_MANIFEST"` — the `.skills` object of the
     global manifest, or `{}` if missing.
   - One `jq` filter emits one row per `(skill, agent)`. The BY value
     is derived inline: `if $mani[name] then "cortex" else "ext" end`.
   - The TSV is piped through `fmt_table → style_name_column → style_by_column`.

3. **`print_folders`** ([cortex.sh:365-399](scripts/cortex.sh#L365-L399)).
   Same idea, but groups by project root. For each `<root>/.claude/skills/`
   or `<root>/skills/` discovered (excluding agent home dirs like
   `~/.claude/`), it reads the per-project manifest at
   `<root>/.cortex.json` and computes BY against that.

`cortex status` never modifies state — it's a pure read of what
`skills list` reports plus the manifests.

---

## 5 · Data formats

### 5.1 Profile (`profiles/<name>.json`)

```jsonc
{
  "name": "system",
  "description": "Base skills installed on every machine.",
  "sources": [
    { "source": "anthropics/skills", "scope": "global",
      "skills": ["skill-creator"], "agents": ["claude-code"] }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Matches the filename stem. Informational; never validated. |
| `description` | no | Picker hint (currently unused). |
| `sources` | yes | Array; may be empty (stub profile). |

Per-source:

| Field | Required | Notes |
|---|---|---|
| `source` | yes | String — provider is detected from the format (§6.1). |
| `scope` | yes | `"global"` or `"project"`. Anything else → source skipped with a warning. |
| `skills` | no | When set, install only these names. When absent, install the whole source. |
| `agents` | no | Per-source override; wins over `CORTEX_AGENTS` env and auto-detect. |

### 5.2 Manifest (both global and project)

```jsonc
{
  "version": 1,
  "skills": {
    "skill-creator": {
      "source":   "anthropics/skills",
      "provider": "github",
      "scope":    "global",
      "profile":  "system",
      "agents":     ["Claude Code", "Continue", "Qwen Code"],
      "first_seen": "2026-05-13T18:19:43Z",   // write-once
      "updated_at": "2026-05-13T19:02:11Z"    // refreshed every run
    }
  }
}
```

| Manifest | Path | Written by | Owned by |
|---|---|---|---|
| Global | `~/.cortex/manifest.json` | sources with `"scope": "global"` | the machine |
| Project | `<cwd>/.cortex.json` | sources with `"scope": "project"` | the project (commit it!) |

`version` is reserved for future schema migrations.

---

## 6 · Algorithms

### 6.1 Provider detection ([lib/source.sh:resolve_source](scripts/lib/source.sh#L16-L58))

Pure pattern match — no network, no `git ls-remote`. The user's choice of
prefix tells us the provider:

```
"/", "~", "~/...", "./...", "../..."     → local   (resolve path; require dir exists)
"http://", "https://", "git://",
"ssh://", "git@..."                       → git     (passed verbatim to skills add)
"owner/name" (exactly one slash, no ws)   → github  (skills.sh registry handles it)
everything else                           → error
```

Strings with two or more slashes (`foo/bar/baz`) are rejected with a
hint to prefix with `./` — that catches the ambiguous case where a user
might have meant a path but wrote it without a leading dot.

### 6.2 Which skill names to track

We need to know *which* skill names belong to a source before we run
`skills add`, because the CLI doesn't tell us in its output. Two cases:

```
if source had explicit `skills` array:
    track exactly those names           ← user told us, trust them
else:
    track list_source_skills(source)    ← ask the CLI via --list
```

`list_source_skills` ([lib/source.sh](scripts/lib/source.sh#L65-L70))
runs `npx skills add <source> --list`, strips ANSI escapes from the
output, and matches the `│    <name>` lines the CLI uses to list each
skill in the source.

If `--list` returns nothing (offline, broken source, transient error)
we warn and proceed without writing manifest entries. This is the
right failure mode: we'd rather under-record than write phantom
entries that don't reflect what the install actually did.

After `skills add` runs, we take a post-install snapshot
(`snapshot_for_scope`). For each expected name we look it up in the
snapshot to grab the *actual* agents list (auto-detect may install to
more agents than the profile requested). If the name isn't present in
`after`, the install failed for that skill — we skip the manifest
entry. Failed installs never appear in the manifest.

### 6.3 Manifest write-once fields

`first_seen` must not change on re-runs. The
[manifest_upsert](scripts/lib/manifest.sh#L44-L64) `jq` filter:

```jq
.skills[$name] = (
  (.skills[$name] // { first_seen: $now })
  + { provider: $provider, source: $source, scope: $scope,
      profile: $prof, agents: $agents, updated_at: $now }
  | del(.adopted)
)
```

The `//` fallback supplies a default object with `first_seen` *only
when the entry is absent*. The `+` merge that follows overrides every
other field. So `first_seen` enters the manifest on first write and
never appears in any subsequent merge object.

`del(.adopted)` strips the legacy field from manifests written by
earlier versions of cortex. It's harmless on fresh manifests.

### 6.4 BY column derivation (in `print_global` / `print_folders`)

`cortex status` emits one row per skill/agent pair, plus extra
universal-mode rows derived from the agent registry (see §6.5). Three
possible BY values:

```jq
# Per-agent symlink rows (one per entry in $skill.agents from skills list):
if $manifest[skill_name] then "cortex" else "ext" end

# Universal rows (one per installed universal-mode agent NOT already
# listed in $skill.agents; only emitted for cortex-managed skills):
"universal"
```

Path column:
- symlink rows → `~/<agent.skillsDir>/<skill>` (looked up in the registry)
- universal rows → `~/.agents/skills/<skill>` (the canonical store)

The relevant manifest depends on the skill's path: global manifest for
skills under `~/.agents/` or `~/.<agent>/`; project manifest at
`<root>/.cortex.json` for any other location.

### 6.5 Agent registry (`scripts/lib/agents.json`)

skills.sh hardcodes ~50 agents in its bundled CLI, each with a
`detectInstalled()` body that does one or two `existsSync()` checks
against a home directory. We embed a normalised copy of that registry
so cortex can answer the same questions (is this agent installed? is
it universal-mode?) without parsing skills CLI output.

The registry is generated by `scripts/refresh-agents.sh`, which:

1. Locates `~/.npm/_npx/*/node_modules/skills/dist/cli.mjs` (warms the
   cache via `npx -y skills --version` if missing).
2. Hands the path to `scripts/lib/extract-agents.mjs`, a small Node
   parser that pulls each `<name>: { displayName, skillsDir, detectInstalled }`
   block out of the bundled JS and emits a JSON record per agent:
   `{ name, displayName, skillsDir, isUniversal, homeDir }`.
3. Writes `scripts/lib/agents.json` (sorted by displayName for stable
   diffs).

The `homeDir` field is a `$HOME`-relative representative path,
derived best-effort from the first `existsSync(...)` call in
`detectInstalled`. Variables that appear inside the body
(`claudeHome`, `codexHome`, `configHome`, `vibeHome`) are resolved via
a small map back to their default $HOME-relative path. `isUniversal`
mirrors skills.sh's own definition: `skillsDir === ".agents/skills"`.

[`scripts/lib/agents.sh`](scripts/lib/agents.sh) exposes:

- `agents_all_json` — full registry as JSON array.
- `agents_installed_names` — names of agents whose home dir exists.
- `agents_installed_json` — same, as a JSON array.
- `agent_lookup <name> <field>` — single-field lookup.

Refresh policy: rerun `scripts/refresh-agents.sh` after a skills.sh
upgrade. The parser sanity-checks the count and refuses to overwrite
if fewer than 20 agents are extracted.

### 6.6 Verbose mode (`-v` / `--verbose`)

`install_one_source` always captures `skills add` output to a temp file.
In default mode the capture is hidden; in verbose mode it's also `tee`'d
to the terminal. The capture exists only to surface error context — on
non-zero exit it's dumped to stderr.

In default mode a compact summary is printed: skill names, the symlink
agents that `skills list --json` reports, and the installed
universal-mode agents from the registry (`agents_installed_json`
intersected with `isUniversal`). In verbose mode the summary is
suppressed because the full CLI output is already on screen.

---

## 7 · Design log

Why things are the way they are. Read this before changing them.

### Why Bash, not Python / Node?

Skills.sh ships as a Node CLI; users already have Node. But cortex
operates *above* it — orchestration, file glue, manifest I/O. Adding a
Python or Node runtime to bootstrap cortex itself would force a second
language toolchain on every machine. Bash + `jq` is enough, runs
everywhere we care about (macOS, Linux, WSL), and the entire codebase
fits in one head.

The cost: no static typing, no test framework. We mitigate with strict
mode (`set -euo pipefail`), small focused functions, and explicit
write-once invariants documented in code comments.

### Why JSON profiles (not YAML / TOML)?

`jq` is already a hard dependency for the manifest. Adding YAML/TOML
means a second parser (`yq` / `toml-cli`) and another tool to install.
JSON is uglier to write but trivial to parse, and we have very small
profiles.

### Why detect the provider instead of an explicit `provider` field?

Earlier iterations had `{ "provider": "github", "repo": "owner/name" }`.
Two fields for the most common case (90 % of entries) is boilerplate.
The auto-detect prefixes (`./`, `https://`, `owner/name`) are
unambiguous and match how users already write skill sources in their
head.

The trade-off: ambiguity at the boundary (`foo/bar/baz`). We reject
those explicitly with an error message that names the fix.

### Why two manifests (global + per-project), not one?

A project's skill setup is part of the project, not the machine. If a
team-mate clones the repo, `cortex install` should give them the same
project skills as the original author. That means the manifest must
travel with the repo — hence `<cwd>/.cortex.json`, committable.

Global skills are the inverse: they belong to the machine, not any one
project. They live in `~/.cortex/`.

### Why no credential storage in cortex?

Git already solves this — Keychain on macOS, libsecret on Linux, Git
Credential Manager cross-platform — and other tools (`gh`, IDE
integrations) benefit from those stores. A cortex-specific store would
either duplicate or fight them. We document setup in the README and
stay out of the credential business.

See the longer discussion at the end of git history if you want
context: PR-by-PR, this question got revisited and rejected three times.

### Why no `adopt` flag any more?

An earlier version of cortex had a third BY value, `adopt`, for
skills that pre-existed on disk before cortex's first install. The
flag was `write-once` — once set, it stayed set even after manual
remove + reinstall. The idea was to give a future `cortex remove`
a way to prompt before deleting skills that pre-dated cortex.

We dropped it because:

1. **It encouraged drift between profile and manifest.** When a
   profile listed a source without an explicit `skills` array and the
   `before/after` diff turned up empty (because all skills were
   already on disk), the fallback was "track every skill currently in
   scope" — even ones that had nothing to do with this source. They
   got `adopted: true` and looked managed, but weren't really.

2. **It was confusing.** Every doc had to explain three values
   instead of two, and the `adopt` semantics ("origin, not current
   state") never felt natural.

3. **The remove-prompt use case can be served differently.** A
   future `cortex remove` can compare `first_seen` to `updated_at`
   or look at how recently the skill was referenced in a profile to
   decide whether to prompt. Origin tracking isn't required for that.

The replacement: `list_source_skills` queries the CLI directly for the
canonical list of skill names in a source. No more diff-and-guess. The
manifest now contains exactly the set of skills that a profile
references and that made it onto disk. Two BY values cover it:
`cortex` (in manifest) and `ext` (not in manifest).

### Why the library split (introduced after the first cut)?

The original layout had `install.sh` as a separate worker script
invoked via `bash scripts/install.sh` from inside `cortex.sh`. That
worked but didn't earn its complexity:

- Nobody called `install.sh` directly — every entry was through the
  `cortex` alias.
- Manifest path logic was duplicated in both files.
- Reading "what does install do" required jumping across scripts.

Extracting `lib/style.sh`, `lib/manifest.sh`, and `lib/source.sh` made
each concern independently inspectable and let `cortex.sh` host the
install loop alongside the other commands.

---

## 8 · Failure modes and invariants

| Invariant | Where it's enforced | Why it matters |
|---|---|---|
| `first_seen` never changes after first write | [lib/manifest.sh:manifest_upsert](scripts/lib/manifest.sh#L44-L64) | The audit trail would lie if it could flip. |
| Manifest only contains skills referenced by a profile (no `adopt` fallback) | [cortex.sh install_one_source](scripts/cortex.sh#L102-L245) + [lib/source.sh:list_source_skills](scripts/lib/source.sh#L65-L70) | Phantom manifest entries were the original cause of the `adopt` confusion; replaced by direct `skills add --list` query. |
| Manifest is only written for skills the post-install snapshot confirms | [cortex.sh:218-221](scripts/cortex.sh#L218-L221) | Failed installs (auth, network, missing `SKILL.md`) leave no record. |
| Project manifest lives at `$PWD`, not the profile's directory | [lib/manifest.sh:manifest_path_for](scripts/lib/manifest.sh#L21-L26) | A profile is portable; the manifest belongs to the project. |
| `provider` is detected from the source string, never user-supplied | [lib/source.sh:resolve_source](scripts/lib/source.sh#L16-L58) | Removes a whole category of typo errors. |
| `cortex status` is read-only | [cortex.sh print_global / print_folders](scripts/cortex.sh#L301-L399) | Inspecting state should never accidentally change it. |

### Edge cases worth knowing

**Invalid profile JSON.** `jq -e . "$profile_file"` runs before the
install loop. We bail with a path the user can pipe back to `jq` to
find the bad line.

**`skills add` exits non-zero but installs anyway.** The post-install
snapshot is authoritative. We only write a manifest entry for a skill
that actually appears in `after`.

**Empty `sources` array.** `thinktank.json` and `web-design.json` ship
this way. We print "No sources" and exit cleanly — not an error.

**Re-run after manual remove.** `npx skills remove X` doesn't touch
the manifest. Next `cortex install` calls `list_source_skills` to
get the source's skill names, re-installs them, and the post-install
snapshot confirms what's back on disk. `first_seen` stays at its
original value (write-once); `updated_at` advances.

**`--list` fails (offline / broken source).** `list_source_skills`
returns an empty list. The install still runs, but we don't write
manifest entries for that source. The skills will appear as `ext` in
`cortex status` until the next successful install. A warning is
emitted.

**Corrupt manifest.** `read_manifest` falls back to `{}` for missing
files, but a present-but-broken file will crash `jq`. We treat that as
a "user repair" situation — printing a useful error and pointing them
at the file path is enough.

---

## 9 · Bash 3.2 compatibility

macOS ships Bash 3.2 (GPLv3 licensing means Apple won't upgrade).
We don't want to require Homebrew Bash, so the codebase avoids:

- **`mapfile` / `readarray`** (Bash 4+) — use
  `while IFS= read -r line; do arr+=("$line"); done < <(…)` instead.
- **`${var,,}` / `${var^^}`** (Bash 4+) — use `tr '[:upper:]' '[:lower:]'`
  if you need case folding.
- **Associative arrays** (`declare -A`) — represent maps as JSON strings
  and parse with `jq`, like `AGENT_LINK_DIRS` in cortex.sh.

The `set -u` foot-gun with empty arrays: use
`${arr[@]+"${arr[@]}"}` to expand to nothing-when-unset and the quoted
elements otherwise. See the `agent_args` / `skill_args` handling in
`install_one_source`.

---

## 10 · Extending

### Add a new provider

1. Add a `case` arm in [lib/source.sh:resolve_source](scripts/lib/source.sh#L16-L58).
   Set `provider` to the new label, `resolved` to whatever string
   `skills add` will accept.
2. If `skills add` doesn't understand the format, handle the
   conversion in `resolve_source` (e.g. clone the URL to a temp dir
   and return that path) — keep the complexity contained.
3. Update §6.1 of this doc and the source-formats table in README.

### Add a new command

1. Write `cmd_<name>()` in `cortex.sh`. Call `print_header` first and
   `print_footer` last so the banner/footer chrome is consistent.
2. Add a line to `usage()` and to the `case "${1:-}" in` dispatcher
   at the bottom of `cortex.sh`.
3. Add the command to the README table.
4. Share helpers from `lib/` instead of re-implementing — anything new
   that touches manifests belongs in `lib/manifest.sh`.

### Implementing `cortex remove`

Sketch (not yet implemented):

- Read manifest. For each entry, optionally `npx skills remove <name>`
  with the recorded scope.
- For each entry, compare `first_seen` against the source's earliest
  mention in the profiles directory. If the skill was tracked long
  before the current profile referenced it, prompt before removing.
- Delete the entry from the manifest only if the post-snapshot
  confirms the skill is actually gone.

### Implementing `cortex update`

Two layers:

- **Refresh skill content** — `npx skills update`. No manifest change.
- **Re-apply profiles** — `cortex install <profile>` is already
  idempotent. A future `--prune` flag could remove manifest entries for
  sources no longer in the profile.

---

## 11 · Glossary

| Term | Meaning |
|---|---|
| **Skill** | A folder with `SKILL.md` plus optional resources. Unit of install. |
| **Source** | A string in a profile that tells `skills add` where to fetch from. Maps to a single skill or a skill repo. |
| **Provider** | The detected type of a source: `github` / `git` / `local`. |
| **Profile** | A `profiles/<name>.json` file listing sources + scopes. The replayable unit. |
| **Scope** | `global` (machine-wide) or `project` (per-CWD). Decides which manifest gets the entry. |
| **Manifest** | The JSON file (`~/.cortex/manifest.json` or `<cwd>/.cortex.json`) where cortex records what it installed. |
| **BY** | The `cortex status` column showing each skill/agent row's relationship to cortex: `cortex` (in manifest, per-agent symlink), `universal` (reachable via the canonical store without a symlink), or `ext` (not in manifest). |
| **ext** | A skill on disk that's not in any cortex manifest — installed manually or by another tool. |
| **universal install** | A `skills add` installation mode where the skill lives only at `~/.agents/skills/<name>` (the canonical store), with no per-agent symlink. Agents that read the canonical store directly (Antigravity, Gemini CLI, Amp, GitHub Copilot, …) see the skill without coretex/the CLI knowing the exact list of agent names. Captured from `skills add` output; we record up to the first ~5 names the CLI prints plus `universal_more` for any remainder. |
| **Snapshot** | The JSON output of `npx skills list --json` at a point in time, filtered to a scope. Used post-install to confirm each expected skill actually landed on disk and to read its `agents` list. |

---

## 12 · References

- Skills CLI: <https://skills.sh>
- Agent Skills spec: <https://agentskills.io/specification>
- This repo: <https://github.com/NETCASE/cortex>
- matklad on `ARCHITECTURE.md`: <https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html>
