-- play [path-or-url] [volume]   : loop a track on the speaker until you press a key.
-- With no source it plays all of Sins from the computer's own disk (Ogg parts in /tracks/sins, needs cc-audio-expand).
local music = require "music"

local DEFAULT = "/tracks/sins"
-- A .dfpwm file or URL works too, e.g. `play https://.../sins.dfpwm`.

local args = { ... }
music.setVolume(tonumber(args[2]) or 0.35)
music.play(args[1] or DEFAULT)
print("Playing " .. (args[1] or DEFAULT) .. ". Press any key to stop.")
parallel.waitForAny(music.run, function() os.pullEvent("key") end)
music.stop()
