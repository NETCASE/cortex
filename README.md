# NETCASE Agent Skills — `cortex`

A collection of [Agent Skills](https://agentskills.io) maintained by [NETCASE GmbH](https://www.netcase.ch), plus a profile-based installer (`cortex`) for replaying curated skill bundles on every machine.

Two roles in one repo:

1. **Skill source** — `skills/` contains the skills NETCASE publishes. Install them anywhere with `npx skills add NETCASE/cortex`. No clone needed.
2. **Installer** — `profiles/` + `scripts/` is YOUR machine setup. It pulls curated bundles (NETCASE + upstream) into the right scope on each machine. Requires cloning the repo.

For implementation details, code references, and how to extend `cortex`, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Install

```sh
# Prereqs
brew install jq node                                                   # jq required; node for npx

# Clone & register the alias
gh repo clone NETCASE/cortex ~/Documents/NETCASE/Code/cortex
cd ~/Documents/NETCASE/Code/cortex
bash install.sh                                                        # adds `cortex` alias to ~/.zshrc or ~/.bashrc
source ~/.zshrc                                                        # or open a new terminal

# Install the system profile (globally, for every detected agent)
cortex install system
```

`install.sh` is idempotent and conflict-aware: re-running it does nothing if the alias is already in place, and it refuses to overwrite an existing `alias cortex=` line that points elsewhere.

In any project that needs framework-specific skills:

```sh
cd ~/Code/my-project
cortex install dev                          # writes ./.claude/skills/ + ./.cortex.json
git add .cortex.json && git commit          # commit the manifest so others get the same setup
```

## Commands

| | |
|---|---|
| `cortex install [-v] [<profile>]` | Install all sources from `profiles/<profile>.json`. No `<profile>` → numbered picker. Default prints a compact summary; `-v` / `--verbose` streams the full `skills.sh` output. |
| `cortex status` | List installed skills. `BY` column: `cortex` (in manifest, per-agent symlink), `universal` (managed skill, accessible to a detected universal-mode agent via the canonical store), or `ext` (not in any manifest). Universal agents are detected at render time from the bundled registry. |
| `cortex detect-agents` | Show which agents skills.sh auto-detect would target on this machine. |
| `cortex --help` | Help. |

`cortex update` and `cortex remove` are placeholders for now — use `npx skills update` and `npx skills remove <name>` directly.

## Profiles

A profile is `profiles/<name>.json`. Schema:

```json
{
  "name": "system",
  "sources": [
    { "source": "anthropics/skills", "scope": "global", "skills": ["skill-creator"] },
    { "source": "NETCASE/cortex",   "scope": "global" }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `source` | yes | A skill source (see formats below) |
| `scope` | yes | `"global"` (→ `~/.agents/skills/`) or `"project"` (→ `$PWD/.claude/skills/`) |
| `skills` | no | Specific skill names; omit = whole source |
| `agents` | no | Specific agent IDs; omit = auto-detect (or `CORTEX_AGENTS` env) |

### Source formats

| Pattern | Provider | Example |
|---|---|---|
| `owner/name` | github (via skills.sh) | `"anthropics/skills"` |
| `https://…`, `git@…`, `ssh://…`, `git://…` | git | `"git@bitbucket.org:org/skills.git"` |
| `/abs/path`, `~/rel`, `./rel` | local filesystem | `"~/work/my-draft"` |

Any URL `git clone` accepts works — including private repos on GitHub, GitLab, Bitbucket (cloud and self-hosted). Authentication is handled by your normal git setup (ssh-agent or credential helper); cortex doesn't store credentials.

## Common tasks

### Add a new source to a profile

Edit `profiles/<name>.json`, append to `sources`, re-run `cortex install <name>`. Idempotent — existing sources are refreshed, the new one is added.

### Install only some skills from a multi-skill repo

```json
{ "source": "anthropics/skills", "scope": "global", "skills": ["skill-creator"] }
```

### Install for specific agents only

Per source (highest precedence):

```json
{ "source": "NETCASE/cortex", "scope": "global", "agents": ["claude-code", "qwen-code"] }
```

Per run (applies to sources without their own `agents`):

```sh
CORTEX_AGENTS=claude-code,qwen-code cortex install system
```

### Develop a skill locally before publishing

```json
{ "source": "~/work/my-draft-skill", "scope": "project" }
```

### Share a project's skill setup

Commit `.cortex.json` and the profile. Collaborators run `cortex install <profile>` in the project root and get the exact same setup.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `jq not found` | `brew install jq` |
| `Invalid JSON in profiles/<name>.json` | Run `jq . profiles/<name>.json` to find the bad line |
| `unrecognized source format` | Check format — `owner/name`, full URL, or path with `./`/`~/`/`/` prefix |
| `fatal: Authentication failed` (HTTPS) | Configure `git config --global credential.helper osxkeychain` and use an app password / PAT |
| `Permission denied (publickey)` (SSH) | Add your key to the host, `ssh-add ~/.ssh/id_ed25519`, test with `ssh -T git@<host>` |
| Skill shows as `ext` in status | Not in the manifest — it was installed outside cortex. Add the source to a profile and re-run `cortex install <profile>` to track it. |

See [ARCHITECTURE.md](ARCHITECTURE.md) for more on what cortex tracks, how `BY` is computed, and edge cases.

## Available skills

<!-- skills:start -->
- **[netcase-bbq](skills/netcase-bbq/)** — Socratic stress-test of a plan or design, ending with a written decision register.
- **[skill-publish](skills/skill-publish/)** — Publish a local Agent Skill folder to the NETCASE/cortex GitHub repository so it becomes installable via `npx skills add NETCASE/cortex`.
<!-- skills:end -->

### Adding a new skill

1. Create `skills/<name>/SKILL.md` ([spec](https://agentskills.io/specification)).
2. Use the [skill-publish](skills/skill-publish/) skill — it validates, commits, pushes, and verifies installation.

## License

MIT — see [LICENSE](LICENSE).
