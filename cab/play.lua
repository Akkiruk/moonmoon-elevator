-- play [path-or-url] [volume]   : loop a track on the speaker until you press a key.
-- With no source it plays the full Sins track from the computer's own disk (515 KB at half rate).
local music = require "music"

local DEFAULT = "/tracks/sins.24k.dfpwm"
-- Optional: stream a full-rate file from a URL instead, e.g. `play https://.../sins.dfpwm`.

local args = { ... }
music.setVolume(tonumber(args[2]) or 1)
music.play(args[1] or DEFAULT)
print("Playing " .. (args[1] or DEFAULT) .. ". Press any key to stop.")
parallel.waitForAny(music.run, function() os.pullEvent("key") end)
music.stop()
