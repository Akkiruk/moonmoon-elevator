# Moon-Moon elevator

ComputerCraft controller for two Create Aeronautics elevators (CC:Tweaked 1.120.2, Minecraft 1.21.1 NeoForge).

- hub/: the machine-room computer that runs the cars
- cab/: the computer on top of each car (display, chimes, music)
- tools/: PC-side helpers (audio conversion)

## Cab music

`cab/music.lua` is the player module, `cab/play.lua` a small program that uses it (`play [url-or-path] [volume]`).
In the cab program: `parallel.waitForAny(music.run, display, rednetLoop)`, then `music.play(src, {fallback=path})`,
`music.stop()`, `music.setVolume(0..3)`, `music.duck(true/false)` (silence during an alarm or chime, resumes after).

### Delivering the track (numbers measured)

DFPWM is 6000 bytes per second. "Sins" is 171.75 s, so `cab/tracks/sins.dfpwm` is 1,030,524 bytes: over the
1,000,000-byte computer disk limit, and the computer also needs room for the code. So:

- Host `cab/tracks/sins.dfpwm` somewhere with a raw URL (for example this repo once it is on GitHub:
  `https://raw.githubusercontent.com/<owner>/<repo>/main/cab/tracks/sins.dfpwm`) and set `DEFAULT_URL` in `play.lua`.
  The player reads the HTTP stream in 4 KB chunks, so memory stays small. The server must have http enabled for that
  host (CC's default rules allow public hosts, and block local addresses).
- `cab/tracks/sins-short.dfpwm` (60 s, 360,000 bytes, faded) goes on the computer as `/tracks/` and plays when the
  URL cannot be reached.

### Other music

`node tools/to-dfpwm.mjs in.mp3 cab/tracks/out.dfpwm [--start 30 --seconds 60 --fade 2 --gain -3]` (ffmpeg with the
dfpwm encoder; the WinGet ffmpeg has it). It prints the size and warns when it will not fit on a disk.
YouTube: this needs a download first, which is not set up here: `yt-dlp -x --audio-format mp3 <link>` (install
yt-dlp yourself), then the command above. https://music.madefor.cc/ exists and converts an uploaded audio file or an
audio URL in the browser, but it is not a YouTube downloader.

### Tests

`cd cab; craftos-mcp test` (uses `cab.world.json`: 1.21.1 / CC 1.120.2, speaker on the right, modem on top).
The emulator has no network, so the http path is not tested; only local files and the fallback are.
