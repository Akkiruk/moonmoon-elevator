-- Check for an update, then run the panel with the updater watching in the background.
local update = require "update"
update.boot("panel")
parallel.waitForAny(function() shell.run("panel") end, function() update.watch("panel") end)
