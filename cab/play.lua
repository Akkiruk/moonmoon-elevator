-- play [url-or-path] [volume]   : loop a track on the speaker until you press a key.
-- With no source it plays the default track (see DEFAULT_URL), falling back to the short local clip.
local music = require "music"

local DEFAULT_URL = "https://raw.githubusercontent.com/OWNER/REPO/main/cab/tracks/sins.dfpwm" -- owner: set this
local FALLBACK = "/tracks/sins-short.dfpwm"

local args = { ... }
music.setVolume(tonumber(args[2]) or 1)
music.play(args[1] or DEFAULT_URL, { fallback = FALLBACK })
print("Playing " .. (args[1] or DEFAULT_URL) .. ". Press any key to stop.")
parallel.waitForAny(music.run, function() os.pullEvent("key") end)
music.stop()
