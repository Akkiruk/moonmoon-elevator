-- Brakes on first, so a slow update check at boot can't leave a car moving, then update and start the hub.
pcall(function() require("hw").new(require("config")):safeStop() end)
local update = require "update"
update.boot("hub")
parallel.waitForAny(function() shell.run("hub.lua") end, function() update.watch("hub") end)
