-- Check for an update, then run the cw with the updater watching in the background.
local update = require "update"
update.boot("cw")
parallel.waitForAny(function() shell.run("cw") end, function() update.watch("cw") end)
