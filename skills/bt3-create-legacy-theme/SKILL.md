---
name: bt3-create-legacy-theme
description: >
  Create a new legacy BT3 theme (on the legacy/10.x branch) in the old monolithic SCSS structure.
  Use this skill whenever the user wants to create a new theme for a company/brand on the legacy branch,
  mentions CssVariables*.scss files, asks about adding a theme to legacy/10.x, or names a company
  (e.g. Sigren, Hinni, Ruefer) in the context of the bt3-design-token project and legacy theme creation.
  Also trigger when the user provides brand colors, a CI/CD color sheet, or a company logo and wants
  a theme derived from it. Do NOT use this skill for porting legacy themes to the new structure —
  use bt3-port-legacy-theme for that instead.
---

# BT3 Legacy Theme Creation

This skill guides the creation of a new legacy BT3 theme — a monolithic SCSS file under `src/styles/00-Company-Variables/` on the `legacy/10.x` branch.

## Project Location

`/Users/novel/Documents/BKW/Projekte/bt3-design-token`

## Color Input Variants

There are three ways a user might provide color information. Determine which variant applies and proceed accordingly:

### V1: Colors are fully known
The user provides exact color values for all primary/secondary shades and contrasts. Simply ask for confirmation and map them directly into the template.

### V2: CI/CD colors are known, scheme needs to be derived
The user provides brand colors (e.g. from a CI/CD guideline or color sheet) but needs a sensible mapping to the M2 shade system (200/300/500/700/900). This is the most common case.

**How to derive a scheme from CI colors:**

| Shade | Role | Typical mapping |
|-------|------|-----------------|
| 200 | Light background (hero, infobox) | Lightest brand color, or a tinted neutral |
| 300 | Secondary background | Same as 200, or slightly different light tone |
| 500 | **Main brand color** — links, buttons, menu indicator | The primary brand color |
| 700 | Hover state, dark accent | Darker variant or secondary dark color (e.g. anthracite) |
| 900 | Dark backgrounds (contact box, footer, teasers) | Same as 500, or darkest brand color |

**Contrast rule:** Light backgrounds (200/300) get dark text contrast. Dark backgrounds (500/700/900) get white contrast. Exception: if the primary-500 color is light (like yellow), use dark contrast.

**Secondary color:** Use the brand's accent color for all secondary shades (300/500/700/900) if only one accent exists. If the brand has multiple accents, map them to different shades.

Present the proposed scheme to the user for confirmation before creating the file.

### V3: Only a logo is available
Read the logo image to extract dominant colors. Identify:
1. The primary brand color (usually the most prominent)
2. Any secondary/accent colors
3. Background color preferences (light/dark)

Then proceed as in V2 to derive a scheme. Be transparent about the extracted colors and ask the user to confirm.

## Step-by-Step Workflow

### 1. Determine Colors (see variants above)

Ask the user which variant applies, or infer from context. Always confirm the final color mapping before creating files.

### 2. Create Feature Branch

```bash
git checkout legacy/10.x
git pull
git checkout -b task/<ticket-number>-<theme-name>
```

Ask the user for the ticket number. Theme file names use PascalCase (e.g., `Sigren.scss`, `BkwGreen.scss`).

### 3. Create the Theme File

Create `src/styles/00-Company-Variables/<ThemeName>.scss` following the template structure below.

### 4. Build & Verify

```bash
npm run build
```

### 5. Commit (do NOT push unless asked)

## Template Structure

Every legacy theme follows this exact structure. Read a reference file first to confirm the pattern hasn't changed:

```bash
git show legacy/10.x:src/styles/00-Company-Variables/SiteProfessional-grey.scss
```

```scss
@import "CssVariablesAngularMaterialDefault";

/* Fonts */
@import "../tokens/font/klint.scss";

/* Base Colors */
$color-white: rgba(255, 255, 255, 1); //#ffffff
$color-black: rgba(0, 0, 0, 1); //#000000

$color-black-100: rgba(242, 242, 242, 1); //#f2f2f2
$color-black-200: rgba(229, 229, 229, 1); //#e5e5e5
$color-black-300: rgba(191, 191, 191, 1); //#bfbfbf
$color-black-400: rgba(148, 148, 148, 1); //#949494
$color-black-500: rgba(118, 118, 118, 1); //#767676
$color-black-700: rgba(77, 77, 77, 1); //#4d4d4d
$color-black-900: rgba(18, 18, 18, 1); //#121212
$color-black-contrast-100: $color-black-900;
$color-black-contrast-200: $color-black-900;
$color-black-contrast-300: $color-black-900;
$color-black-contrast-400: $color-black-900;
$color-black-contrast-500: $color-white;
$color-black-contrast-700: $color-white;
$color-black-contrast-900: $color-white;

$color-yellow-500: rgba(255, 204, 0, 1); //#ffcc00
$color-yellow-contrast-500: $color-black-900;

$color-blue-300: rgba(133, 207, 232, 1); //#85cfe8
$color-blue-500: rgba(0, 127, 167, 1); //#007fa7
$color-blue-700: rgba(0, 75, 118, 1); //#004b76
$color-blue-900: rgba(0, 45, 105, 1); //#002d69
$color-blue-contrast-300: $color-black-900;
$color-blue-contrast-500: $color-white;
$color-blue-contrast-700: $color-white;
$color-blue-contrast-900: $color-white;

$color-green-300: rgba(214, 215, 0, 1); //#d6d700
$color-green-500: rgba(0, 135, 45, 1); //#00872d
$color-green-700: rgba(0, 95, 55, 1); //#005f37
$color-green-900: rgba(0, 72, 64, 1); //#004840
$color-green-contrast-300: $color-black-900;
$color-green-contrast-500: $color-white;
$color-green-contrast-700: $color-white;
$color-green-contrast-900: $color-white;

$color-red-300: rgba(169, 23, 42, 1);
$color-red-500: rgba(147, 9, 27, 1);
$color-red-700: rgba(128, 5, 21, 1);
$color-red-900: rgba(101, 0, 12, 1);
$color-red-contrast-300: $color-white;
$color-red-contrast-500: $color-white;
$color-red-contrast-700: $color-white;
$color-red-contrast-900: $color-white;

/* <BrandName> Brand Colors */
$color-<brand>-<name>: rgba(<R>, <G>, <B>, 1); //#<hex>
// ... define all custom brand colors as variables here

/* Theme Colors */
// Primary
$color-primary-200: <LIGHT-COLOR>;
$color-primary-300: <LIGHT-COLOR>;
$color-primary-500: <MAIN-BRAND-COLOR>;
$color-primary-700: <DARK-ACCENT>;
$color-primary-900: <DARKEST-OR-MAIN>;
// Primary Contrast
$color-primary-contrast-200: <DARK-TEXT>;
$color-primary-contrast-300: <DARK-TEXT>;
$color-primary-contrast-500: <WHITE-OR-DARK>;
$color-primary-contrast-700: <WHITE>;
$color-primary-contrast-900: <WHITE>;

// Secondary
$color-secondary-300: <ACCENT-COLOR>;
$color-secondary-500: <ACCENT-COLOR>;
$color-secondary-700: <ACCENT-COLOR>;
$color-secondary-900: <ACCENT-COLOR>;
// Secondary Contrast
$color-secondary-contrast-300: <CONTRAST>;
$color-secondary-contrast-500: <CONTRAST>;
$color-secondary-contrast-700: <CONTRAST>;
$color-secondary-contrast-900: <CONTRAST>;

/* Alerts */
// ... (see Alert Config section below)

@import "CssVariablesAngularMaterial";
```

## Alert Config

Alerts use the standard token colors (green/red/yellow/blue), NOT the theme's brand colors. Copy this block verbatim — it's identical across most legacy themes:

```scss
/* Alerts */
$alert-success-text-color: $color-green-contrast-500;
$alert-success-background-color: $color-green-500;
$alert-success-button-primary-color: $color-green-500;
$alert-success-button-primary-color-hover: $color-green-700;
$alert-success-button-primary-background-color: $color-green-contrast-500;
$alert-success-button-secondary-color: $color-green-contrast-500;
$alert-success-button-secondary-border-color: rgba($color-green-contrast-500, 0.75);
$alert-success-button-secondary-border-color-hover: $color-green-contrast-500;

$alert-error-text-color: $color-red-contrast-500;
$alert-error-background-color: $color-red-500;
$alert-error-button-primary-color: $color-red-500;
$alert-error-button-primary-color-hover: $color-red-700;
$alert-error-button-primary-background-color: $color-red-contrast-500;
$alert-error-button-secondary-color: $color-red-contrast-500;
$alert-error-button-secondary-border-color: rgba($color-red-contrast-500, 0.75);
$alert-error-button-secondary-border-color-hover: $color-red-contrast-500;

$alert-warn-text-color: $color-yellow-contrast-500;
$alert-warn-background-color: $color-yellow-500;
$alert-warn-button-primary-color: $color-yellow-contrast-500;
$alert-warn-button-primary-color-hover: $color-yellow-contrast-500;
$alert-warn-button-primary-background-color: $color-white;
$alert-warn-button-secondary-color: $color-yellow-contrast-500;
$alert-warn-button-secondary-border-color: rgba($color-yellow-contrast-500, 0.5);
$alert-warn-button-secondary-border-color-hover: $color-yellow-contrast-500;

$alert-info-text-color: $color-blue-contrast-300;
$alert-info-background-color: $color-blue-300;
$alert-info-button-primary-color: $color-blue-contrast-300;
$alert-info-button-primary-color-hover: $color-blue-contrast-300;
$alert-info-button-primary-background-color: $color-white;
$alert-info-button-secondary-color: $color-blue-contrast-300;
$alert-info-button-secondary-border-color: rgba($color-blue-contrast-300, 0.5);
$alert-info-button-secondary-border-color-hover: $color-blue-contrast-300;
```

Some themes override the info alert to use the primary brand color instead of blue — this is an exception, not the default. Only do this if the user explicitly requests it or the brand's primary IS a blue tone that works for info alerts.

## Font

Most themes use Klint: `@import "../tokens/font/klint.scss";`

Other font options exist but are rare. Check `src/styles/tokens/font/` for alternatives if needed.

## Reference Files

| File | Purpose |
|------|---------|
| `src/styles/00-Company-Variables/SiteProfessional-grey.scss` | Clean example with inline custom colors |
| `src/styles/00-Company-Variables/Aek.scss` | Example using `colors.$color-*` token references |
| `src/styles/00-Company-Variables/_CssVariablesAngularMaterialDefault.scss` | Default `!default` null values |
| `src/styles/00-Company-Variables/_CssVariablesAngularMaterial.scss` | CSS custom properties + Angular Material config |
| `src/styles/tokens/variables/colors.scss` | Available color tokens |

## Key Conventions

- **File naming**: PascalCase, matching existing patterns (e.g., `Sigren.scss`, `BkwGreen.scss`, `SiteProfessional-grey.scss`)
- **Branch**: Always branch from `legacy/10.x`, format `task/<ticket>-<theme-name>`
- **Base colors block**: The black/yellow/blue/green/red block is standard — copy from reference, don't modify unless the brand needs different utility colors
- **Brand colors section**: Define custom brand colors as named variables (e.g., `$color-sigren-blue`) before using them in primary/secondary assignments — this improves readability
- **Only define shades 200/300/500/700/900**: The legacy system only uses these 5 shades. All others (50, 100, 400, 600, 800, A-variants) are set to `null` via `_CssVariablesAngularMaterialDefault`
- **Commit but don't push**: Unless the user explicitly asks to push

## Publishing & Versioning

The legacy branch (`legacy/10.x`) has **no CI/CD pipeline** — unlike `develop`, which auto-builds via Azure Pipelines on push. Legacy releases must be published manually.

### Versioning scheme

- **Development**: `X.Y.Z-SNAPSHOT` in both `pom.xml` and `package.json` (Maven convention)
- **Release**: Remove `-SNAPSHOT` suffix → `X.Y.Z`
- The `pom.xml` version is the source of truth — during pipeline builds, Maven syncs it to `package.json` via the `npm-version` execution
- **Existing versions on Nexus cannot be overwritten** — you'll get an E400 error. If a version already exists, bump to the next patch (e.g. `10.7.0` → `10.7.1`)

### Manual publish workflow

```bash
# 1. Set release version (remove -SNAPSHOT)
npm version 10.7.1 --no-git-tag-version

# 2. Build dist
npm run build

# 3. Publish to Nexus (auth token is in ~/.npmrc)
npm run release
```

No `npm login` needed — the auth token (`NpmToken.*`) is already configured in `~/.npmrc` for the `@bt3` scope pointing to `https://nexus-cloud.bkw.ch/repository/npm-external/`.

### After publishing

Update the version in the **TYPO3 project** (`bkw-typo3-cms`):
- `app/packages/bt3_components/Resources/Private/Build/package.json` → `"@bt3/design-tokens": "10.7.1"`
- Run `yarn install` to update the lockfile

### PR workflow for legacy themes

When merging feature branches into `legacy/10.x`:
- Ensure `pom.xml` and `package.json` versions match `legacy/10.x` (rebase if needed)
- The PR comments in Azure DevOps often flag version conflicts — these are the most common blocker
- After merge, the SNAPSHOT version on `legacy/10.x` remains unchanged until a release is triggered

### Version history context

The TYPO3 project may reference a version higher than what `legacy/10.x` shows in its SNAPSHOT — this is because releases were published manually at various points. Check Nexus to see which versions actually exist before choosing your version number.

## Common Pitfalls

- **Missing `@import "CssVariablesAngularMaterialDefault"` at the top** — this sets all undefined shades to `null !default`
- **Missing `@import "CssVariablesAngularMaterial"` at the bottom** — this generates the CSS custom properties and Angular Material palette
- **Contrast colors wrong way around** — light colors on light backgrounds are invisible. Always verify contrast makes sense
- **Using brand yellow for warn alerts** — don't override the standard `$color-yellow-500` alert color with the brand's yellow. Alerts use fixed token colors
