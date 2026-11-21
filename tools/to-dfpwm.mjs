#!/usr/bin/env node
// Turn any audio file ffmpeg can read into CC:Tweaked DFPWM (mono; --rate 48000 is full quality, 24000 or 16000 are stored at half or a third and the player upsamples).
//   node tools/to-dfpwm.mjs in.ogg out.dfpwm [--seconds 90] [--start 0] [--fade 2] [--gain -3]
// Name a low-rate file like sins.24k.dfpwm: the player reads the rate from the name.
// ffmpeg is taken from $FFMPEG, then the usual WinGet install, then PATH.
import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";

const WINGET =
  process.env.LOCALAPPDATA +
  "\Microsoft\WinGet\Packages\Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe\ffmpeg-8.0.1-full_build\bin\ffmpeg.exe";
const ffmpeg = process.env.FFMPEG || (process.env.LOCALAPPDATA && existsSync(WINGET) ? WINGET : "ffmpeg");

const [input, output, ...rest] = process.argv.slice(2);
if (!input || !output || input.startsWith("--")) {
  console.error("usage: node tools/to-dfpwm.mjs <input> <output.dfpwm> [--seconds N] [--start N] [--fade N] [--gain dB] [--rate 48000|24000|16000]");
  process.exit(2);
}
const opt = { seconds: 0, start: 0, fade: 0, gain: 0, rate: 48000 };
for (let i = 0; i < rest.length; i += 2) {
  const k = rest[i].replace(/^--/, "");
  if (!(k in opt) || rest[i + 1] === undefined || isNaN(Number(rest[i + 1]))) {
    console.error("bad option " + rest[i]);
    process.exit(2);
  }
  opt[k] = Number(rest[i + 1]);
}

const filters = [];
if (opt.gain) filters.push(`volume=${opt.gain}dB`);
if (opt.fade && opt.seconds) {
  filters.push(`afade=t=in:d=${opt.fade}`, `afade=t=out:st=${Math.max(0, opt.seconds - opt.fade)}:d=${opt.fade}`);
}
const args = ["-y", "-hide_banner", "-loglevel", "error"];
if (opt.start) args.push("-ss", String(opt.start));
args.push("-i", input);
if (opt.seconds) args.push("-t", String(opt.seconds));
args.push("-vn", "-ac", "1", "-ar", String(opt.rate));
if (filters.length) args.push("-af", filters.join(","));
args.push("-c:a", "dfpwm", "-f", "dfpwm", output);

const r = spawnSync(ffmpeg, args, { stdio: "inherit" });
if (r.error || r.status !== 0) {
  console.error("ffmpeg failed" + (r.error ? ": " + r.error.message : "") + " (needs a build with the dfpwm encoder)");
  process.exit(1);
}
const bytes = statSync(output).size;
console.log(`${output}: ${bytes} bytes, ${(bytes / (opt.rate / 8)).toFixed(1)} s${bytes > 1000000 ? " (too big for a 1 MB computer disk: stream it)" : ""}`);
