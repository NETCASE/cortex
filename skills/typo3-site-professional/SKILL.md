---
name: typo3-site-professional
description: >
  Guide for creating a new "Site Professional" in the BKW TYPO3 system. Use
  this skill whenever the user mentions setting up a new site pro, running
  bt3sitegenerator:clisteps, onboarding a new company website, or doing the
  local finishing steps after the backend wizard ran on production. Also use it
  when the user mentions fixing logos, SCSS design tokens, config.yaml PID, or
  OG images for a new site. This skill knows the full two-phase workflow
  (production backend wizard + local CLI steps), all known gotchas (ddev
  config YAML corruption, wrong PID in config.yaml, inherited design tokens),
  and the exact file paths involved.
---

# TYPO3 Site Professional — Setup Guide

This skill covers the complete process of creating a new "Site Professional"
in the BKW TYPO3 stack. The process has two phases:

1. **Production (Backend Wizard)** — done via TYPO3 backend, creates all DB entries
2. **Local (CLI + manual)** — run after syncing the DB locally

---

## Phase 1: Production Backend Wizard

Done by the developer/PM directly in the TYPO3 backend on production.

Steps the wizard executes automatically (for reference):
- Copy model site pages in DB → new root page gets a new PID
- Create fileadmin folder and file mount
- Create BE group, assign to pages
- Set home page title, update template UIDs, update slugs
- Create `tx_bt3_dynamic_site_settings` record (stores the serialized DTO)
- Create scheduler tasks

The wizard output ends with:
```
- Record in tx_bt3_dynamic_site_settings has been created.
  Please continue setup locally `./app/vendor/bin/typo3 bt3sitegenerator:clisteps <PID>` in your CLI.
```

**Capture the PID** from that message — you'll need it for Phase 2.

Key inputs collected during the wizard:
- **Model** (e.g. `10970-SitesProfessional`, `10972-BuildingSolutions`)
- **Identifier** (slug-style, e.g. `sigren-engineering-ag`) → converted to CamelCase for folder names
- **Domain** (e.g. `sigren-engineering.ch`)
- **Title** (e.g. `Sigren Engineering AG`)

---

## Phase 1.5: Verify Backend Configuration (on Production)

**Do this before syncing the DB locally and before running clisteps.**

After the wizard finishes, go to the TYPO3 backend on production:

**Module: "Sites" (Seitenkonfiguration)**

Open the newly created site and check the color scheme list. The model copies
**all** its color schemes to the new site — typically far more than needed.

**Delete all color schemes that the company does NOT use.** For most new sites,
this means keeping only the one agreed-upon scheme (usually the default/standard
entry). Leaving unused schemes in place will cause `clisteps` to generate
unnecessary SCSS files and logo placeholders for those schemes.

> Example: The `BuildingSolutions` model has 6 color schemes (blau, blue,
> green, orange, red, yellow). A new company using only a single blue theme
> needs only 1. Delete the other 5 before running clisteps.

**If the user has already run `clisteps` with too many schemes**, ask:

> "Hast du `clisteps` schon ausgeführt, bevor die überzähligen Farbschemas
> gelöscht wurden? Dann haben wir jetzt unnötige SCSS-Files und Logo-Varianten
> im Repo. Soll ich die aufräumen, oder lassen wir es vorerst so?"

If they want cleanup, delete:
- `CompanyStyles/<Identifier>-<unused-scheme>.scss` for each unused scheme
- `Sites/<Identifier>/Resources/Public/Images/Logo/logo-<unused-scheme>.svg`
- `Sites/<Identifier>/Resources/Public/Images/Logo/logo-small-<unused-scheme>.svg`
- `Sites/<Identifier>/Resources/Public/Icons/TCA/pages-color_scheme-<unused-scheme>.svg`

After cleaning up, sync the DB locally, then proceed to Phase 2.

---

## Phase 2: Local Setup

### Step 0: Sync DB from production

Make sure the local DB is up to date before proceeding.

### Step 1: Run CLI steps (inside DDEV)

```bash
ddev exec php -d memory_limit=512M ./app/vendor/bin/typo3 bt3sitegenerator:clisteps <PID>
```

> Always run inside DDEV (`ddev exec`). Running directly on the host fails
> because MySQL is only accessible inside the container.
>
> Add `-d memory_limit=512M` — the default 128M limit causes a fatal error
> during DI container compilation.

This runs two steps automatically:

**Step 70 — StateSiteConfiguration:**
- Copies `EXT:bt3_site_bkw/Models/<modelPid>-*/` → `EXT:bt3_site_bkw/Sites/<Identifier>/`
- Copies the model's `Site/config.yaml`, replaces model PID with new site PID
- Creates TYPO3 site config symlink in `app/config/sites/<Identifier>`

**Step 80 — StateCreateSiteConfigurationFiles:**
- Copies fileadmin folder structure from model
- Creates placeholder SVG logos per color scheme in `Sites/<Identifier>/Resources/Public/Images/Logo/`
- Creates color scheme TCA icons in `Sites/<Identifier>/Resources/Public/Icons/TCA/`
- Creates `CompanyStyles/<Identifier>.scss` (and variants per color scheme) in `EXT:bt3_components`
- Adds the site's short hostname to `.ddev/config.yaml`

---

### Step 2: Fix known issues after clisteps

#### 2a. Fix `config.yaml` root page ID

The `Site/config.yaml` often retains the model's PID instead of the new site's PID.
Check and fix manually:

```yaml
# app/packages/bt3_site_bkw/Sites/<Identifier>/Site/config.yaml
imports:
  - bt3SiteGeneratorSettingsForRootpageUid: &rootPageId <NEW_PID>   # ← must be new PID, not model PID
  ...
rootPageId: *rootPageId
```

#### 2b. Fix `.ddev/config.yaml` YAML corruption

The clisteps command rewrites the **entire** `.ddev/config.yaml` using Symfony
YAML dump. This causes two problems:

**Problem 1 — Empty arrays become maps (breaks DDEV):**
Symfony YAML serializes empty PHP arrays as `{  }` (flow map) instead of `[]`
(flow sequence). DDEV expects lists and will refuse to start.

Check and fix:
```yaml
# Wrong (after clisteps):
additional_fqdns: {  }
web_environment: {  }

# Correct:
additional_fqdns: []
web_environment: []
```

**Problem 2 — Full file reformat (noisy diff):**
The Symfony dump also reformats all values (`'8.3'` → `"8.3"`, multiline
strings get re-escaped, etc.), producing a large and misleading git diff that
has nothing to do with the actual site setup. After fixing Problem 1, review
the diff with `git diff .ddev/config.yaml` and revert any purely cosmetic
reformatting if it matters for the PR.

**If clisteps failed on first attempt** (due to Problem 1) and had to be
re-run: the DDEV hostname step may have been skipped on the failed attempt.
Verify that the new site's short hostname was added to `additional_hostnames`.
If not, add it manually before running `ddev restart`.

---

### Step 3: Fix CompanyStyles SCSS design tokens

The CLI creates SCSS files based on the model's color scheme configuration.
These often point to the **wrong design token** (inherited from the model's
other sites). Update them to the correct token for this company.

Files are in:
```
app/packages/bt3_components/Resources/Private/Build/CompanyStyles/<Identifier>.scss
app/packages/bt3_components/Resources/Private/Build/CompanyStyles/<Identifier>-<colorscheme>.scss
```

Each file looks like:
```scss
$fonts-path: '../Assets/Fonts';
$polyfluid: true;
@import 'node_modules/@bt3/design-tokens/dist/00-Company-Variables/<TokenName>.scss';
@import 'node_modules/@bt3/design-tokens/dist/00-Company-Variables/_CssVariablesCMS.scss';
@import 'temporary-overwrite';
```

> **Import path format:** The `clisteps` command generates files with the
> `node_modules/@bt3/...` prefix. This works for many tokens but can fail for
> tokens that internally import Angular Material (e.g. `BkwEngineering.scss`).
> When updating the import, use `@bt3/design-tokens/...` (without `node_modules/`)
> — this is resolved via the sass `--load-path` and is more reliable:
>
> ```scss
> // Correct:
> @import '@bt3/design-tokens/dist/00-Company-Variables/BkwEngineering.scss';
> @import '@bt3/design-tokens/dist/00-Company-Variables/_CssVariablesCMS.scss';
> ```

**If the company reuses an existing design token** (most common): update the
import to point to the correct existing token, e.g. `BkwEngineering.scss`.

**If the company needs a new design token**: see "New Design Token" section below.

Common existing tokens to reuse:
- `BkwEngineering.scss` — standard engineering blue
- `Bkw.scss` — BKW standard

---

### Step 4: Replace logos

The CLI creates placeholder BKW logos. Replace them with the company's actual logo.

Logo locations:
```
Sites/<Identifier>/Resources/Public/Images/logo.svg         ← main logo
Sites/<Identifier>/Resources/Public/Images/Logo/logo-default.svg
Sites/<Identifier>/Resources/Public/Images/Logo/logo-<colorscheme>.svg
Sites/<Identifier>/Resources/Public/Images/Logo/logo-small-<colorscheme>.svg
```

Copy the company's SVG into all relevant positions. Typically the same SVG
works for all variants at this stage. For colored-background variants (used
when the BE user switches color scheme), a white/inverted version is needed —
but the blue default works as a placeholder for non-default schemes.

#### Small logo (`logo-small-<colorscheme>.svg`) — special attention for individual company logos

For standardized square BKW logos the small variant is usually fine as-is.
For **individual company logos** (horizontal wordmarks, unique shapes), always
evaluate the small variant separately:

**If the customer delivers a dedicated small logo** (e.g. icon-only, cropped
version): use it directly — no further work needed.

**If only one logo file is available** (common case), check whether the SVG
works on a dark/colored background:

- Display the SVG mentally or in a browser on a **black background**.
- Typical problems: dark logo on dark background → invisible; or aspect ratio
  too extreme for the small slot.

If the logo does NOT work on a dark background (most horizontal wordmarks
with dark text fall into this category), add a **white background rect**:

```svg
<style type="text/css">
  .st0{fill:#FFFFFF;}
  .st1{fill:<brand-color>;}  <!-- original logo color -->
</style>
<rect class="st0" width="<viewBox-width>" height="<viewBox-height>"/>
<!-- original logo paths, class changed from st0 → st1 -->
```

The rect must span the full viewBox.

**ViewBox / Aspect Ratio:** The `bfe-global-navigation` web component renders
the small logo constrained by `--logo-height-*: 20px` (set via CSS token) and
`width: auto`. This means the rendered height is always fixed — but only if the
**aspect ratio** matches what the header slot expects. All working individual
company logos use approximately a **2.72:1 ratio** (e.g. `155×57`). If the
source logo's viewBox has a wider ratio (e.g. Sigren's original `230×80` =
2.875:1), the rendered logo will be shorter than the header bar, leaving a
dark gap at the bottom.

Fix: adjust the viewBox so the ratio matches ~2.72:1, while keeping the logo
paths centred within the new bounds. Example for a `230×80` source:

```svg
<!-- Target ratio: 230 / 2.72 ≈ 85px height -->
<!-- Center: original content y=6.9..73.1 → add 2.5px top+bottom -->
viewBox="0 -2.5 230 85"
<rect x="0" y="-2.5" width="230" height="85" class="st0"/>  <!-- white -->
```

Reference: Sigren `logo-small-blue.svg` — viewBox `0 -2.5 230 85`,
navy `#21335C` logo on white `#FFFFFF` background.

#### OG Image (`open-graph.png`)

The CLI places a generic BKW placeholder OG image. Always replace it with a
company-specific one.

**Location:**
```
Sites/<Identifier>/Resources/Public/Images/open-graph.png
```

**Format:** 600×600 px PNG (used across all existing site pros).

**Recipe — brand color background + white logo (most common case):**

1. Check what logo files are available (SVG preferred). If only a colored logo
   SVG exists, use it with the fill color changed to `#FFFFFF`.

2. Create a temporary SVG:
   ```svg
   <svg viewBox="0 0 600 600" width="600" height="600" xmlns="http://www.w3.org/2000/svg">
     <!-- Background = brand/Hausfarbe -->
     <rect width="600" height="600" fill="<#BRANDCOLOR>"/>
     <!-- Logo centered, scaled to ~400px wide -->
     <!-- Original viewBox 0 0 230 80 → scale=400/230≈1.739, height≈139px -->
     <!-- Center: translate(100, 230) = (600-400)/2, (600-139)/2 -->
     <g transform="translate(100, 230) scale(1.739)">
       <!-- all logo <path> elements with fill="#FFFFFF" -->
     </g>
   </svg>
   ```
   Adjust `scale` and `translate` based on the logo's original viewBox dimensions:
   - Target logo width on canvas: ~400px → `scale = 400 / viewBox-width`
   - Logo height on canvas: `viewBox-height * scale`
   - Center X: `(600 - 400) / 2 = 100`
   - Center Y: `(600 - logoHeightOnCanvas) / 2`

3. Convert to PNG with `rsvg-convert` (available on macOS via Homebrew):
   ```bash
   rsvg-convert -w 600 -h 600 /tmp/og.svg -o /tmp/og.png
   ```

4. Preview the PNG (Claude can display it with the Read tool), then copy to the
   site's `Images/` folder.

**Reference:** Sigren — `#21335C` background, white logo, scale 1.739, translate(100, 230.4).

---

### Step 5: DDEV restart + cache flush

The new hostname needs `sudo` to write to `/etc/hosts`. Run in your terminal:

```bash
ddev restart
ddev exec ./app/vendor/bin/typo3 cache:flush
```

---

### Step 6: Frontend build

After updating SCSS files, rebuild the frontend via the DDEV command:

```bash
ddev app-build-frontend
```

This runs `yarn --frozen-lockfile && yarn build` including prettier/lint checks and
theme compilation. This is the correct command for a new site — it compiles the
new `CompanyStyles/<Identifier>.scss` into CSS.

> `ddev app-build-frontend-local` is faster but skips themes — it will NOT
> compile a newly added CompanyStyle. Only use it for JS/non-theme changes.

**If the build fails with a Prettier error** on a CompanyStyle file, run:
```bash
ddev exec bash -c "cd app/packages/bt3_components && yarn prettier:write"
```
Then retry `ddev app-build-frontend`.

---

## Azure DevOps Board

**Board:** `https://bkwag.visualstudio.com/FIEE/_boards/board/t/Sites%20Professional/Stories`
**Team:** Sites Professional (`b451cc5d-3367-43ac-be62-34d2486ec952`)
**Template Story:** `72286` ("Temlate Site Professional")
**PAT:** In der Umgebungsvariable `AZURE_PAT` oder beim Nutzer erfragen.

### Board-Columns und State-Mapping

| Board-Spalte | State (API) |
|---|---|
| Potenzial | `New` |
| First contact / Angebot (Doing/Done) | `New` |
| **Shell erstellen / Übergabe an Kunde (Doing/Done)** | **`Active`** |
| Go Live | `Resolved` |
| Live | `Resolved` |
| Abgeschlossen | `Closed` |

Die Story **muss im State `Active`** sein, wenn wir lokal die Site erstellen
(= Spalte "Shell erstellen / Übergabe an Kunde: Doing").

### Vorgehen beim Start

**1. Story suchen** (nach Domain-Name):
```bash
curl -s -u ":$AZURE_PAT" \
  "https://bkwag.visualstudio.com/FIEE/_apis/wit/wiql?api-version=7.1" \
  -H "Content-Type: application/json" \
  -d '{"query": "SELECT [System.Id],[System.Title],[System.State] FROM WorkItems WHERE [System.AreaPath] UNDER \"FIEE\\Sites Professional\" AND [System.Title] CONTAINS \"<domain>\""}' \
  | python3 -c "import sys,json; items=json.load(sys.stdin)['workItems']; print(items)"
```

**2a. Story existiert** → Task "Site Professional erstellen" auf `Active` setzen:
```bash
# Task-ID des "Site Professional erstellen" Tasks der Story ermitteln,
# dann State updaten:
curl -s -u ":$AZURE_PAT" \
  "https://bkwag.visualstudio.com/FIEE/_apis/wit/workItems/<TASK_ID>?api-version=7.1" \
  -X PATCH -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/fields/System.State","value":"Active"}]'
```


**2b. Keine Story vorhanden** → Story + alle Tasks aus Template 72286 kopieren:

```python
# Claude führt dies direkt via Python/curl aus:
# 1. Story erstellen (Title = domain.tld, Area = FIEE\Sites Professional, State = New)
#    → Bewusst "New" statt "Active", damit die Story in "Potenzial" landet
#    → "Shell erstellen" kann via API nicht direkt angesteuert werden (see below)
# 2. Alle 24 Tasks aus 72286 als neue Tasks anlegen, Parent = neue Story
# 3. Task "Site Professional erstellen" auf Active setzen
```

> **Bekannte API-Limitation:** Azure DevOps erlaubt es nicht, Karten via REST
> API zwischen Spalten zu verschieben, die denselben State teilen. "Site abbauen"
> und "Shell erstellen / Übergabe an Kunde" sind beide `Active` — deshalb landet
> eine neu erstellte `Active`-Story in der falschen Spalte ("Site abbauen").
>
> **Workaround:** Story mit State `New` erstellen → nach dem Erstellen den
> Nutzer anweisen, die Karte **manuell per Drag & Drop** in
> "Shell erstellen / Übergabe an Kunde: Doing" zu verschieben.
> Danach kann der State via API auf `Active` gesetzt werden, ohne die Spalte
> zu ändern.

Für die Ausführung: Claude holt die Task-Titel direkt von der Template-Story
(`GET /workItems?ids=78373,72278,...`) und erstellt sie via
`POST /workItems/$Task` mit Hierarchy-Reverse-Relation zur neuen Story.

### Vorgehen nach Abschluss

Wenn der lokale Setup fertig ist (Build erfolgreich, Site erreichbar):

Task "Site Professional erstellen" auf `Closed` setzen:
```bash
curl -s -u ":$AZURE_PAT" \
  "https://bkwag.visualstudio.com/FIEE/_apis/wit/workItems/<TASK_ID>?api-version=7.1" \
  -X PATCH -H "Content-Type: application/json-patch+json" \
  -d '[{"op":"add","path":"/fields/System.State","value":"Closed"}]'
```

---

## New Design Token (when needed)

If the company needs its own color scheme (not reusing an existing token):

1. In the `bt3-design-token` repo (separate repository), create a new theme file
   under `00-Company-Variables/` with the company's brand colors.

2. Publish a new version of the npm package `@bt3/design-tokens`.

3. Update the version reference in `app/packages/bt3_components/` wherever
   `@bt3/design-tokens` is declared as a dependency.

4. Run `yarn install` inside `bt3_components` to pull the new version.

5. Update the `CompanyStyles/<Identifier>.scss` files to import the new token.

6. Run `yarn build`.

> The team is migrating from legacy v10.x to the new `develop/main` branch
> of bt3-design-token — check which branch is current before adding a new token.

---

## File Map (quick reference)

| What | Path |
|------|------|
| Site config | `app/packages/bt3_site_bkw/Sites/<Identifier>/Site/config.yaml` |
| TYPO3 site symlink | `app/config/sites/<Identifier>` → points to above |
| Logos | `app/packages/bt3_site_bkw/Sites/<Identifier>/Resources/Public/Images/` |
| TCA icons | `app/packages/bt3_site_bkw/Sites/<Identifier>/Resources/Public/Icons/TCA/` |
| CompanyStyles SCSS | `app/packages/bt3_components/Resources/Private/Build/CompanyStyles/` |
| Model folders | `app/packages/bt3_site_bkw/Models/<pid>-<Name>/` |
| DDEV config | `.ddev/config.yaml` |

---

## Checklist

- [ ] (on Production) Site wizard completed, PID noted
- [ ] (on Production) Backend "Sites" module: color schemes cleaned up — only keep what the company actually uses
- [ ] DB synced from production
- [ ] `ddev exec php -d memory_limit=512M ./app/vendor/bin/typo3 bt3sitegenerator:clisteps <PID>`
- [ ] `config.yaml` rootPageId = new site PID (not model PID)
- [ ] `.ddev/config.yaml` has no `{  }` syntax (fix to `[]`)
- [ ] CompanyStyles SCSS files point to correct design token
- [ ] Logos replaced with company logo SVG
- [ ] OG image updated (or noted as pending)
- [ ] `ddev restart` (run manually, needs sudo)
- [ ] `ddev exec ./app/vendor/bin/typo3 cache:flush`
- [ ] `yarn build` in `app/packages/bt3_components`
