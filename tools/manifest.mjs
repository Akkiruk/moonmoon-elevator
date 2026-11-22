// Writes manifest.json: for each computer role, the files it gets and a sha of each. The computers compare
// these with what they last installed (update/update.lua). Run it before pushing a change:
//   node tools/manifest.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// installed name on the computer -> path in the repo
const roles = {
  hub: {
    "startup.lua": "hub/startup.lua", "hub.lua": "hub/hub.lua", "elevator.lua": "hub/elevator.lua",
    "hw.lua": "hub/hw.lua", "config.lua": "hub/config.lua", "counterweight.lua": "hub/counterweight.lua",
    "dispatch.lua": "hub/dispatch.lua", "motion.lua": "hub/motion.lua", "panel.lua": "hub/panel.lua",
  },
  cab: { "startup.lua": "cab/startup.lua", "cab.lua": "cab/cab.lua", "music.lua": "cab/music.lua", "play.lua": "cab/play.lua" },
  doorsensor: { "startup.lua": "doorsensor/startup.lua", "doorsensor.lua": "cab/doorsensor.lua" },
  landing: { "startup.lua": "landing/startup.lua", "landing.lua": "landing/landing.lua" },
  panel: { "startup.lua": "panel/startup.lua", "panel.lua": "panel/panel.lua" },
  inspect: { "startup.lua": "inspect/startup.lua", "inspect.lua": "inspect/inspect.lua" },
  plaque: { "startup.lua": "plaque/startup.lua", "plaque.lua": "plaque/plaque.lua" },
  cw: { "startup.lua": "counterweight/startup.lua", "cw.lua": "counterweight/cw.lua" },
};

const out = { roles: {} };
for (const [role, files] of Object.entries(roles)) {
  files["update.lua"] = "update/update.lua";
  out.roles[role] = {};
  for (const [name, src] of Object.entries(files)) {
    // GitHub serves what git stores, which is LF, so hash that
    const text = readFileSync(join(root, src)).toString("utf8").replace(/\r\n/g, "\n");
    const sha = createHash("sha1").update(text).digest("hex").slice(0, 12);
    out.roles[role][name] = { src, sha };
  }
}
writeFileSync(join(root, "manifest.json"), JSON.stringify(out, null, 1) + "\n");
console.log("manifest.json: " + Object.keys(out.roles).join(", "));
