---
name: bt3-port-legacy-theme
description: >
  Port a BT3 legacy theme (from the legacy/10.x branch) to the new design-token structure.
  Use this skill whenever the user mentions porting, migrating, or converting a legacy theme,
  references CssVariables*.scss files from the old structure, wants to create a new theme
  _config.scss from an existing legacy theme, or mentions "legacy theme to new structure".
  Also trigger when the user mentions theme names like ActVisual, Onyx, AEK etc. in the
  context of the bt3-design-token project and migration/porting.
---

# BT3 Legacy Theme Porting

This skill guides the process of converting a legacy BT3 theme (SCSS variables file) into the new modular theme structure used in bt3-design-token v11+.

## Project Location

`/Users/novel/Documents/BKW/Projekte/bt3-design-token`

## Overview

Legacy themes live on the `legacy/10.x` branch as monolithic SCSS files under:
```
src/styles/00-Company-Variables/<ThemeName>.scss
```

The new structure uses a modular approach with two files per theme:
```
src/resources/themes/<theme-name>/
  _config.scss   # All color definitions, palettes, alert config, font config
  index.scss     # Single line: @forward "config" show $theme-config;
```

## Step-by-Step Porting Workflow

### 1. Create Feature Branch

```bash
git checkout develop
git pull
git checkout -b task/<ticket-number>-<theme-name>
```

Theme folder names use lowercase-hyphenated format (e.g., `act-visual`, `bkw-green`).

### 2. Read the Legacy Theme

Switch to `legacy/10.x` temporarily to read the source file, or use `git show`:

```bash
git show legacy/10.x:src/styles/00-Company-Variables/<ThemeName>.scss
```

Extract these color groups from the legacy file:

| Group | Variables to find |
|-------|-------------------|
| **Primary** | `$color-primary-200`, `$color-primary-300`, `$color-primary-500`, `$color-primary-700`, `$color-primary-900` + contrast variants |
| **Secondary** | `$color-secondary-300`, `$color-secondary-500`, `$color-secondary-700`, `$color-secondary-900` + contrast variants |
| **Alert Success** | `$alert-success-*` (text, background, button colors) |
| **Alert Error** | `$alert-error-*` |
| **Alert Warn** | `$alert-warn-*` |
| **Alert Info** | `$alert-info-*` |
| **Font** | Which `@import` for the font (usually `klint.scss`) |

### 3. Map Colors to Existing Tokens

Before hardcoding rgba values, check if the legacy color matches an existing token in `src/resources/tokens/_colors-m2.scss`. Common mappings:

| Legacy color | Token equivalent |
|-------------|-----------------|
| `rgba(0, 135, 45, 1)` green-500 | `colors-m2.$color-green-500` |
| `rgba(0, 95, 55, 1)` green-700 | `colors-m2.$color-green-700` |
| `rgba(147, 9, 27, 1)` red/error | `colors-m2.$color-dark-red-500` |
| `rgba(128, 5, 21, 1)` red-700 | `colors-m2.$color-dark-red-700` |
| `rgba(133, 207, 232, 1)` blue-300 | `colors-m2.$color-blue-300` |
| `rgba(255, 204, 0, 1)` yellow | `colors-m2.$color-red-200` (yes, yellow is stored here) |
| white | `colors-m2.$color-bkw-white` |
| black (#121212) | `colors-m2.$color-bkw-black` |

Colors that don't match any token get defined as direct `rgba()` values in the `_config.scss`.

### 4. Create `_config.scss`

**CRITICAL: No null values allowed.** Every M2 shade (50–900) and accent shade (A50–A900) must have a real color value. Legacy themes only define a few shades (typically 200/300/500/700/900) — calculate the missing ones.

#### Calculating Missing Shades

Use `sass:color.mix()` to interpolate between known anchor values. Define the brand's key colors as private variables first, then compute all shades:

```scss
@use "sass:color";

/* Brand Colors */
$_brand-main: rgba(33, 51, 92, 1); // the 500 color
$_brand-light: rgba(199, 209, 217, 1); // the 200/300 color
$_brand-dark: rgba(28, 28, 28, 1); // the 700 color

// Primary — interpolate between known anchors
$color-primary-50: color.mix(#fff, $_brand-light, 50%);
$color-primary-100: color.mix(#fff, $_brand-light, 25%);
$color-primary-200: $_brand-light;
$color-primary-300: $_brand-light;
$color-primary-400: color.mix($_brand-light, $_brand-main, 50%);
$color-primary-500: $_brand-main;
$color-primary-600: color.mix($_brand-main, $_brand-dark, 50%);
$color-primary-700: $_brand-dark;
$color-primary-800: color.mix($_brand-dark, $_brand-main, 50%);
$color-primary-900: $_brand-main; // or different if legacy defines it differently
```

For secondary colors where the legacy uses the same value for all shades, generate a proper tonal palette from the base color:

```scss
$_accent: rgba(255, 249, 0, 1); // secondary base color

$color-secondary-50: color.mix(#fff, $_accent, 88%);
$color-secondary-100: color.mix(#fff, $_accent, 70%);
$color-secondary-200: color.mix(#fff, $_accent, 50%);
$color-secondary-300: $_accent; // legacy anchor
$color-secondary-400: color.mix(#fff, $_accent, 15%);
$color-secondary-500: $_accent; // legacy anchor
$color-secondary-600: color.mix(#000, $_accent, 13%);
$color-secondary-700: $_accent; // legacy anchor
$color-secondary-800: color.mix(#000, $_accent, 46%);
$color-secondary-900: $_accent; // legacy anchor
```

#### Accent Shades (A50–A900)

Legacy themes don't use accent shades. Mirror the regular shades:

```scss
$color-primary-A50: $color-primary-50;
$color-primary-A100: $color-primary-100;
// ... through A900
```

#### Contrast Values

Every shade needs a contrast value. Light shades get dark contrast, dark shades get white:

```scss
// Light shades → dark contrast
$color-primary-contrast-50: colors-m2.$color-bkw-black;
$color-primary-contrast-100: colors-m2.$color-bkw-black;
$color-primary-contrast-200: colors-m2.$color-bkw-black;
$color-primary-contrast-300: colors-m2.$color-bkw-black;
// Dark shades → white contrast
$color-primary-contrast-400: colors-m2.$color-bkw-white;
$color-primary-contrast-500: colors-m2.$color-bkw-white;
// ... etc.
```

Accent contrasts mirror the regular contrasts:

```scss
$color-primary-contrast-A50: $color-primary-contrast-50;
// ... through A900
```

#### Alert Config

Use `map.merge()` on the default alert config. Keys must be quoted strings:

```scss
$alert-config: map.merge(
  alert.$alert-config,
  (
    "alert-success-text-color": colors-m2.$color-bkw-white,
    "alert-success-background-color": colors-m2.$color-green-500,
    // ... all alert overrides
  )
);
```

#### M3 Palettes

Legacy themes have no M3 colors. The `@use "../default-theme-colors" as *` import provides blue-based M3 fallback values via `!default`. Reference these in the `$_palettes` map exactly as done in the reference themes.

#### $theme-config Map

The final config map follows this exact structure:

```scss
$theme-config: (
  m2: (
    colors: (
      primary: ( /* all primary-* keys */ ),
      secondary: ( /* all secondary-* keys */ ),
    ),
    font: font.$font-config,
    components: (
      alert: $alert-config,
    ),
  ),
  m3: (
    colors: $_palettes,
    font: font.$font-config-m3,
    components: (
      alert: alert.$alert-config-m3,
    ),
  ),
  default-spacing: spacings.$default-spacing,
);
```

### 5. Create `index.scss`

Always exactly one line:

```scss
@forward "config" show $theme-config;
```

### 6. Bump Version

Update `package.json` version. A new theme is a feature, so bump the minor version:
- `11.3.4` -> `11.4.0`

### 7. Verify

Run the build to check for SCSS compilation errors:

```bash
npm run build
```

Then grep to confirm no null values leaked through:

```bash
grep -r ": null;" src/resources/themes/<theme-name>/
```

This MUST return zero results.

## Reference Files

When porting, read these files for patterns:

| File | Purpose |
|------|---------|
| `src/resources/themes/sigren/_config.scss` | Full example with `color.mix()` interpolation and custom colors |
| `src/resources/themes/act-visual/_config.scss` | Another example with interpolated shades |
| `src/resources/themes/bkw-green/_config.scss` | Example using token references for all colors |
| `src/resources/themes/_default-theme-colors.scss` | M3 `!default` fallback values (used via wildcard import) |
| `src/resources/tokens/_colors-m2.scss` | All available M2 color tokens |
| `src/resources/tokens/components/alert.scss` | Default alert config maps |

## Common Pitfalls

- **NEVER use `null` for any shade** — every M2 shade (50–900, A50–A900) and its contrast must have a real color value. Use `sass:color.mix()` to calculate missing shades
- **Don't forget `@use "sass:color"`** — needed for `color.mix()` interpolation
- **Don't forget `@use "sass:map"`** — needed for `map.merge()` in the alert config
- **Alert map keys must be quoted strings** — `"alert-success-text-color"` not `alert-success-text-color`
- **The wildcard import `as *`** is only for `default-theme-colors` — all other imports use named namespaces
- **Legacy `$color-yellow-500`** maps to `colors-m2.$color-red-200` in the token system (historical naming)
- **M3 palette variables** (like `$color-primary-0`, `$color-primary-10`) come from `default-theme-colors` via the wildcard import — don't redefine them unless the theme has custom M3 colors
- **Neutral palette in M3** has extra non-standard steps (4, 6, 12, 17, 22, 24, 87, 90, 92, 94, 96) — copy the exact structure from a reference theme
