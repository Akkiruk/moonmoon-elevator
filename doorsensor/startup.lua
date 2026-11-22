-- Check for an update, then run the doorsensor with the updater watching in the background.
local update = require "update"
update.boot("doorsensor")
parallel.waitForAny(function() shell.run("doorsensor") end, function() update.watch("doorsensor") end)
