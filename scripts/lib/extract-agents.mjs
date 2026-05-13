#!/usr/bin/env node
// extract-agents.mjs — parse skills.sh `dist/cli.mjs` and emit the agent registry.
//
// Usage:
//   node extract-agents.mjs <path-to-cli.mjs> > agents.json
//
// Output: JSON array of { name, displayName, skillsDir, isUniversal, homeDir }
// where homeDir is a $HOME-relative single representative path (best-effort,
// derived from the first `existsSync(...)` call in detectInstalled).

import { readFileSync } from "node:fs";

const cliPath = process.argv[2];
if (!cliPath) {
  console.error("usage: extract-agents.mjs <cli.mjs>");
  process.exit(1);
}
const src = readFileSync(cliPath, "utf8");

// Map JS variables that appear inside detectInstalled() back to their
// $HOME-relative representative paths. Defaults match what skills.sh would
// produce when the corresponding env var is unset.
const VAR_MAP = {
  claudeHome: ".claude",
  codexHome:  ".codex",
  configHome: ".config",
  vibeHome:   ".vibe",
};

// Walk the file, matching `<id>: { ... }` blocks at one tab of indent.
// Quoted (`"claude-code":`) and bare (`amp:`) identifiers both occur.
const blockRe = /^\t(?:"([a-z][a-z0-9-]*)"|([a-z][a-z0-9-]*)): \{$/gm;
const agents = [];
let m;
while ((m = blockRe.exec(src)) !== null) {
  const name = m[1] || m[2];
  // Walk braces from the opening { to find the matching }.
  let i = m.index + m[0].length;
  let depth = 1;
  while (i < src.length && depth > 0) {
    const c = src[i++];
    if (c === "{") depth++;
    else if (c === "}") depth--;
  }
  const block = src.slice(m.index + m[0].length, i - 1);

  const displayName = block.match(/displayName:\s*"([^"]+)"/)?.[1];
  const skillsDir = block.match(/skillsDir:\s*"([^"]+)"/)?.[1];
  if (!displayName || !skillsDir) continue;

  // Pull the detectInstalled body and find the first existsSync target.
  const detectBody = block.match(/detectInstalled:[^]*?return ([^;]+);/)?.[1] ?? "";
  // Patterns we recognise (in priority order; first hit wins):
  //   existsSync(join(home, "X"))                → "X"          (under $HOME)
  //   existsSync(join(<varHome>, "X"))           → VAR_MAP+"/X" (varHome maps to a relative dir)
  //   existsSync(join(process.cwd(), "X"))       → "X"          (best-effort, $HOME-relative)
  //   existsSync(<varHome>)                      → VAR_MAP
  let homeDir = "";
  let match;
  if ((match = detectBody.match(/existsSync\(join\(home, "([^"]+)"\)\)/))) {
    homeDir = match[1];
  } else if ((match = detectBody.match(/existsSync\(join\(([a-z][a-zA-Z]+Home), "([^"]+)"\)\)/))) {
    const base = VAR_MAP[match[1]] ?? "";
    homeDir = base ? `${base}/${match[2]}` : "";
  } else if ((match = detectBody.match(/existsSync\(join\(process\.cwd\(\), "([^"]+)"\)\)/))) {
    homeDir = match[1];
  } else if ((match = detectBody.match(/existsSync\(([a-z][a-zA-Z]+Home)\)/))) {
    homeDir = VAR_MAP[match[1]] ?? "";
  }

  agents.push({
    name,
    displayName,
    skillsDir,
    isUniversal: skillsDir === ".agents/skills",
    homeDir,
  });
}

// Drop the `universal` pseudo-entry — it's a synthetic target in skills CLI,
// not a real agent.
const filtered = agents.filter((a) => a.name !== "universal");

// Sort by displayName for stable diffs.
filtered.sort((a, b) => a.displayName.localeCompare(b.displayName));

console.log(JSON.stringify(filtered, null, 2));
