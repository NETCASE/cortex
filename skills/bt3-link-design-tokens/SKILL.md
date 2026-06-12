---
name: bt3-link-design-tokens
description: >
  Link the bt3-design-token package locally into the bkw-typo3-cms project for rapid frontend testing.
  Use this skill whenever the user wants to test design token changes locally in the TYPO3 frontend,
  mentions "linking", "yarn link", "npm link" in the context of bt3-design-token or bkw-typo3-cms,
  wants to preview a theme in the browser before publishing, or says things like "ich will das Theme
  testen" or "kann ich das lokal ausprobieren". Also trigger when the user has just created or modified
  a theme and wants to verify it compiles correctly in the TYPO3 build pipeline.
---

# BT3 Design Tokens — Local Linking

This skill enables a fast feedback loop between the `bt3-design-token` repo (where themes/tokens are defined) and the `bkw-typo3-cms` repo (where they're consumed and compiled into CSS).

## Project Paths

| Project | Path |
|---------|------|
| Design Tokens | `/Users/novel/Documents/BKW/Projekte/bt3-design-token` |
| TYPO3 CMS | `/Users/novel/Documents/BKW/Projekte/bkw-typo3-cms` |

## How It Works

The TYPO3 project consumes `@bt3/design-tokens` as an npm package. Each company theme in `CompanyStyles/<Theme>.scss` imports its token file. The import style depends on the version:

**v11+ (new structure, `develop` branch):**
```scss
@use '@bt3/design-tokens/themes/sigren' as theme;
@use '@bt3/design-tokens/styles/00-Company-Variables/_CssVariablesCMS.scss' with (
  $theme-config: theme.$theme-config
);
```

**v10 (legacy structure, `legacy/10.x` branch):**
```scss
@import '@bt3/design-tokens/dist/00-Company-Variables/<Theme>.scss';
@import '@bt3/design-tokens/dist/00-Company-Variables/_CssVariablesCMS.scss';
```

By linking the local design-token repo, changes to token files are immediately available in the TYPO3 build — no need to publish to the npm registry first.

## Step-by-Step

### 1. Build the design-token dist

Always build first — the TYPO3 project imports from the built output, not from source.

```bash
cd /Users/novel/Documents/BKW/Projekte/bt3-design-token
npm run build
```

### 2. Register the link (design-token repo)

**This step differs between v10 and v11** because of how `npm publish` works:

**v11+ (`develop` branch):** The package is published from `dist/` (`npm publish ./dist`), so the published package root = `dist/`. Register the link from `dist/`:

```bash
cd /Users/novel/Documents/BKW/Projekte/bt3-design-token/dist
yarn link
```

**v10 (legacy `legacy/10.x`):** The package is published from the repo root (`npm publish`), and `dist/` is listed in `"files"`. Register the link from the repo root:

```bash
cd /Users/novel/Documents/BKW/Projekte/bt3-design-token
yarn link
```

**Why this matters:** When the TYPO3 project imports `@bt3/design-tokens/themes/sigren`, yarn resolves this relative to wherever the link was registered. In v11, if you link from the repo root, imports fail with "Can't find stylesheet" because `themes/` only exists inside `dist/`, not at the repo root. Linking from `dist/` makes the paths match what the published package would look like.

Only needs to be done once (persists until `yarn unlink`). If you see "already registered", the link is still active from a previous session — that's fine, but verify it points to the correct directory (root vs dist) for your branch.

### 3. Consume the link (TYPO3 repo)

```bash
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/app/packages/bt3_components
yarn link @bt3/design-tokens
```

This replaces the `node_modules/@bt3/design-tokens` directory with a symlink to the local design-token repo.

### 4. Ensure the CompanyStyles entry exists

Each theme needs a corresponding file in the TYPO3 project at:
```
app/packages/bt3_components/Resources/Private/Build/CompanyStyles/<Theme>.scss
```

**v11+ pattern:**
```scss
$fonts-path: '../Assets/Fonts';
$polyfluid: true;

@use '@bt3/design-tokens/themes/<theme-name>' as theme;
@use '@bt3/design-tokens/styles/00-Company-Variables/_CssVariablesCMS.scss' with (
  $theme-config: theme.$theme-config
);
@use 'temporary-overwrite';
```

**v10 pattern:**
```scss
$fonts-path: '../Assets/Fonts';
$polyfluid: true;
@import '@bt3/design-tokens/dist/00-Company-Variables/<Theme>.scss';
@import '@bt3/design-tokens/dist/00-Company-Variables/_CssVariablesCMS.scss';
@import 'temporary-overwrite';
```

### 5. Node version

The TYPO3 Build package requires **Node 22**. If you're using nvm:

```bash
source ~/.nvm/nvm.sh
nvm use 22
```

The design-token repo (v10) uses Node 20, so you may need to switch between versions. v11 also uses Node 22.

### 6. Compile and test

```bash
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/app/packages/bt3_components/Resources/Private/Build
yarn run themes:compile
```

This compiles all `CompanyStyles/*.scss` into `../../Public/Css/*.css`. Check the output:
```bash
ls -la ../../Public/Css/<Theme>.css
```

A successfully compiled theme CSS is typically 5-120 KB depending on the version (v11 themes are smaller).

If the build fails on a *different* theme (e.g. a theme that exists in CompanyStyles but whose token file isn't in the linked dist), that's expected — the linked repo may not have all themes on the current branch. Your theme compiling successfully is what matters.

### 7. Preview in browser

If ddev is running:
```bash
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms
ddev start   # if not already running
```

Then visit the site in the browser. The theme CSS is loaded based on the TYPO3 site configuration.

### 8. Iterate

After making changes to token files in the design-token repo:
```bash
cd /Users/novel/Documents/BKW/Projekte/bt3-design-token
npm run build
```

Then recompile in the TYPO3 project:
```bash
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/app/packages/bt3_components/Resources/Private/Build
yarn run themes:compile
```

No need to re-link — the symlink persists.

### 9. Unlink when done

When you're finished testing and ready to go back to the published package:

```bash
# In the TYPO3 project
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/app/packages/bt3_components
yarn unlink @bt3/design-tokens
yarn install --force   # restore the published version from registry

# In the design-token repo (from wherever you registered the link)
cd /Users/novel/Documents/BKW/Projekte/bt3-design-token/dist  # or repo root for v10
yarn unlink
```

The `yarn install --force` is important — without it, the symlink is removed but the published package isn't restored.

## Where @bt3/design-tokens is used in the TYPO3 project

The package appears as a dependency in three places:

| Package | Path |
|---------|------|
| Build | `app/packages/bt3_components/Resources/Private/Build/package.json` |
| StaticPages | `app/packages/bt3_components/Resources/Private/StaticPages/package.json` |
| Angular | `app/packages/bt3_components/Resources/Private/Angular/package.json` |

Linking at `app/packages/bt3_components` covers all three since they share `node_modules` via the workspace.

## ddev and Linking

`ddev app-build-frontend` runs `yarn --frozen-lockfile` (see `.ddev/commands/web/app-build-frontend`), which reinstalls all packages and **destroys the yarn link**. This is unavoidable — yarn install always replaces symlinks with real packages.

**Recommended workflow for local theme testing:**

```bash
# 1. Build the full frontend once (this breaks the link, but that's OK)
ddev app-build-frontend

# 2. Re-establish the link
cd /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/app/packages/bt3_components
yarn link @bt3/design-tokens

# 3. Recompile only themes (fast, ~2s)
cd Resources/Private/Build
yarn run themes:compile
```

After step 2, you can iterate (edit tokens → `npm run build` → `yarn run themes:compile`) without re-linking. Only if you run `ddev app-build-frontend` or `yarn install` again will the link break.

**To skip the full frontend build entirely**, create a skip file:
```bash
touch /Users/novel/Documents/BKW/Projekte/bkw-typo3-cms/.skip-npm-install
```
This causes `ddev app-build-frontend` to exit immediately (see the `if` check in the script). Remove the file when you want normal builds again.

## Common Issues

- **"Can't find stylesheet to import" for YOUR theme** — Either you forgot `npm run build`, or (v11 only) you registered the link from the repo root instead of `dist/`. Fix: `cd dist && yarn link`, then re-link in the TYPO3 project
- **Build fails on a different theme** — Another CompanyStyles entry references a token file that doesn't exist in your branch's dist. Not your problem — ignore it
- **Changes not reflected after rebuild** — Make sure you ran `npm run build` in the design-token repo before `themes:compile` in the TYPO3 project
- **yarn install removes the link** — Running `yarn install` in the TYPO3 project breaks the link. Re-run `yarn link @bt3/design-tokens` after any install
- **Node version mismatch** — TYPO3 Build requires Node 22. Use `nvm use 22` before running `yarn run themes:compile`
- **"already registered" but wrong directory** — If switching between v10 and v11, first `yarn unlink` from the old location, then re-register from the correct one
