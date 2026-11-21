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

Plain DFPWM is 6000 bytes per second, so Sins (171.75 s) would be 1,030,524 bytes: over the 1,000,000-byte disk.
So the track is stored at half rate: `cab/tracks/sins.24k.dfpwm`, 515,262 bytes (about 3000 bytes per second, top
frequency 12 kHz). The player sees "24k" in the file name, decodes, and stretches it back to 48 kHz by linear
interpolation (`16k` names work too, 3x). That leaves about 480 KB for the elevator code. `play` with no argument plays it.
Cost: about 8 ms of CPU per 0.68 s chunk at Cobalt speed (the emulator's slow-VM mode), roughly 1%.

Optional: any full-rate file or URL also plays (`play https://.../x.dfpwm`; the server needs http enabled for that host).

### Making the track

Sins is red_exp's `assets/red_exp/sounds/sins.ogg` (unzip it from the mod jar), converted with
`node tools/to-dfpwm.mjs sins.ogg cab/tracks/sins.24k.dfpwm --rate 24000` (ffmpeg with the dfpwm encoder; WinGet's has it). Use `--rate 24000` for the half-rate file (`--rate 16000` is smaller and duller). Any other audio file works the same; for YouTube, run
`yt-dlp -x <link>` yourself first (not installed here).

### Two cars

Each cab computer runs its own copy of the player: no files are written and nothing is shared between computers, so
two cars playing at once (even the same URL) do not interfere.

### Tests

`cd cab; craftos-mcp test --timeout 60` (uses `cab.world.json`: 1.21.1 / CC 1.120.2, speaker on the right, modem on top).
The emulator has no network, so the http path is not tested; only local files and the fallback are.
