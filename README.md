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

All of Sins (171.75 s) is in `cab/tracks/sins/`: 15 Ogg Vorbis parts of 12 s (mono, 48 kHz, about 39 kbit/s) and a
`list.txt`, 896 KB in all, so it fits the 1,000,000-byte disk with the code and needs no config change. The pack's
cc-audio-expand mod decodes each part in Java (`cc.audio.ogg`) and `speaker.playAudioEx` plays the 16-bit samples, so
Lua does no work per sample. `play` with no argument plays it.

Why the old player sounded broken: the cab is on a Sable sub-level, and Sable wraps every sound played there in its
own object. cc-audio-expand (which also takes over plain `speaker.playAudio` on this pack) then never finds its sound
again, so every packet starts as a new sound the moment it reaches the client. The server sends each packet half a
second early, so the packets overlapped by 0.5 s and the old sound's cleanup wiped the new one's queue: choppy,
doubled audio. The player now starts with a 0.525 s silent packet and sends whole-tick packets, which lines the server's
timing up so each packet arrives as the last one ends (more in `cab/music.lua`). Ogg packets are 8-bit so each one
can be 2.7 s: `playAudioEx` takes at most 131072 bytes, mono and 48 kHz only, so nothing longer is possible. 1-bit DFPWM also
adds hiss above the music's own treble, hence Ogg. The whole song as one Ogg file would decode in one go and stall
every computer for about half a second, hence the parts.

Without cc-audio-expand a track folder doesn't open and `{fallback = path}` is used. DFPWM files and URLs still play
(`play https://.../x.dfpwm`; the server needs http enabled for that host), as do half-rate files (`name.24k.dfpwm`).

### Volume and range

The default music volume is 0.35 (`set mmlift.volume 0.5` and reboot to change it). Minecraft lets a speaker sound
carry `max(volume, 1) * attenuation_distance` blocks, fading linearly to nothing, and cc-audio-expand leaves the
distance at the default 16. `resourcepack/` sets it to 4 for cc-audio-expand's speaker stream only (chimes and the
alarm are note blocks and keep their range). Zip the folder's contents as `resources.zip` in the world folder, or
put the folder in the instance's `resourcepacks` and turn it on.

### Making the track

Sins is red_exp's `assets/red_exp/sounds/sins.ogg` (unzip it from the mod jar), converted with
`node tools/to-ogg.mjs sins.ogg cab/tracks/sins` (ffmpeg with libvorbis; WinGet's has it). `--kbps` sets the bitrate:
47 is about the most that still fits. `tools/to-dfpwm.mjs` still makes DFPWM files. Any other audio file works the
same; for YouTube, run `yt-dlp -x <link>` yourself first (not installed here).

### Two cars

Each cab computer runs its own copy of the player: no files are written and nothing is shared between computers, so
two cars playing at once (even the same URL) do not interfere.

### Tests

`cd cab; craftos-mcp test --timeout 60` (uses `cab.world.json`: 1.21.1 / CC 1.120.2, speaker on the right, modem on top).
The emulator has no network, so the http path is not tested; only local files and the fallback are.
