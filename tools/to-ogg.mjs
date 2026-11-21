#!/usr/bin/env node
// Make a track folder for the cab player: the song cut into short Ogg Vorbis parts (mono, 48 kHz) plus list.txt.
//   node tools/to-ogg.mjs in.ogg cab/tracks/sins [--kbps 47] [--part 12] [--gain 0]
// The cab decodes one part at a time with cc-audio-expand's cc.audio.ogg (Java), so no Lua per-sample work.
// A whole-song decode blocks the computer thread for about half a second, which every computer in the world
// waits out with computer_threads=1; a 12 s part is about 35 ms. Each part is encoded with a little extra audio
// on both sides that the player cuts off again (list.txt says how much), so the joins are clean.
// ffmpeg is taken from $FFMPEG, then the usual WinGet install, then PATH.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const WINGET =
  process.env.LOCALAPPDATA +
  "\\Microsoft\\WinGet\\Packages\\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\\ffmpeg-8.0.1-full_build\\bin\\ffmpeg.exe";
const ffmpeg = process.env.FFMPEG || (process.env.LOCALAPPDATA && existsSync(WINGET) ? WINGET : "ffmpeg");

const [input, outDir, ...rest] = process.argv.slice(2);
if (!input || !outDir || input.startsWith("--")) {
  console.error("usage: node tools/to-ogg.mjs <input> <track folder> [--kbps 47] [--part 12] [--gain dB]");
  process.exit(2);
}
const opt = { kbps: 47, part: 12, gain: 0 };
for (let i = 0; i < rest.length; i += 2) {
  const k = rest[i].replace(/^--/, "");
  if (!(k in opt) || isNaN(Number(rest[i + 1]))) {
    console.error("bad option " + rest[i]);
    process.exit(2);
  }
  opt[k] = Number(rest[i + 1]);
}

const RATE = 48000;
const PAD = 4096; // samples; two long Vorbis blocks, so the edge of each encode lands in audio that gets cut

function run(args) {
  const r = spawnSync(ffmpeg, ["-y", "-hide_banner", "-loglevel", "error", ...args], { stdio: "inherit" });
  if (r.error || r.status !== 0) {
    console.error("ffmpeg failed" + (r.error ? ": " + r.error.message : "") + " (needs libvorbis)");
    process.exit(1);
  }
}

const tmp = join(tmpdir(), "to-ogg-" + process.pid);
mkdirSync(tmp, { recursive: true });
const full = join(tmp, "full.raw");
run(["-i", input, "-vn", "-ac", "1", "-ar", String(RATE), ...(opt.gain ? ["-af", `volume=${opt.gain}dB`] : []), "-f", "s16le", full]);
const pcm = readFileSync(full);
const total = pcm.length / 2;

mkdirSync(outDir, { recursive: true });
for (const f of readdirSync(outDir)) if (f.endsWith(".ogg") || f === "list.txt") rmSync(join(outDir, f));

const per = Math.round(opt.part * RATE);
const lines = [];
let bytes = 0;
for (let start = 0, n = 1; start < total; start += per, n++) {
  const keep = Math.min(per, total - start);
  const from = Math.max(0, start - PAD);
  const to = Math.min(total, start + keep + PAD);
  const raw = join(tmp, n + ".raw");
  writeFileSync(raw, pcm.subarray(from * 2, to * 2));
  const name = String(n).padStart(2, "0") + ".ogg";
  run(["-f", "s16le", "-ar", String(RATE), "-ac", "1", "-i", raw, "-c:a", "libvorbis", "-b:a", opt.kbps + "k", join(outDir, name)]);
  bytes += statSync(join(outDir, name)).size;
  lines.push(`${name} ${start - from} ${keep}`);
}
writeFileSync(join(outDir, "list.txt"), lines.join("\n") + "\n");
rmSync(tmp, { recursive: true, force: true });
console.log(`${outDir}: ${lines.length} parts, ${bytes} bytes, ${(total / RATE).toFixed(2)} s`);
