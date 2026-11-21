# Moon-Moon elevator

ComputerCraft controller for two Create Aeronautics elevators (CC:Tweaked 1.120.2, Minecraft 1.21.1 NeoForge).

- hub/: the machine-room computer that runs the cars
- cab/: the computer on top of each car (display, chimes, music)
- tools/: PC-side helpers (audio conversion)

## Cab music

`cab/music.lua` is the player module, `cab/play.lua` a small program that uses it (`play [url-or-path] [volume]`).
In the cab program: `parallel.waitForAny(music.run, display, rednetLoop)`, then `music.play(src, {fallback=path})`,
`music.stop()`, `music.setVolume(0..3)`, `music.duck(true/false)` (silence during an alarm or chime, resumes after).

### The track (fits on the cab computer)

Plain DFPWM is 6000 bytes per second, so all of Sins (171.75 s) would be 1,030,524 bytes, over the 1,000,000-byte disk.
The cab plays the first 150 s at full 48 kHz instead, with a 3 s fade at the end: `cab/tracks/sins.dfpwm`, 900,000
bytes, about 100 KB left for the elevator code. The half-rate version it replaced (24 kHz, stretched back up in Lua)
sounded muffled. `play` with no argument plays it. Half-rate files (`name.24k.dfpwm`, `name.16k.dfpwm`) still work.

Optional: any full-rate file or URL also plays (`play https://.../x.dfpwm`; the server needs http enabled for that host).

### Making the track

Sins is red_exp's `assets/red_exp/sounds/sins.ogg` (unzip it from the mod jar), converted with
`node tools/to-dfpwm.mjs sins.ogg cab/tracks/sins.dfpwm --seconds 150 --fade 3 --rate 48000` (ffmpeg with the dfpwm encoder; WinGet's has it). `--rate 24000` makes a half-rate file instead. Any other audio file works the same; for YouTube, run
`yt-dlp -x <link>` yourself first (not installed here).

### Two cars

Each cab computer runs its own copy of the player: no files are written and nothing is shared between computers, so
two cars playing at once (even the same URL) do not interfere.

### Tests

`cd cab; craftos-mcp test --timeout 60` (uses `cab.world.json`: 1.21.1 / CC 1.120.2, speaker on the right, modem on top).
The emulator has no network, so the http path is not tested; only local files and the fallback are.
