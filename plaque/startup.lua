-- Check for an update, then run the plaque with the updater watching in the background.
local update = require "update"
update.boot("plaque")
parallel.waitForAny(function() shell.run("plaque") end, function() update.watch("plaque") end)
