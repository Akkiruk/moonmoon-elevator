-- Check for an update, then run the cab with the updater watching in the background.
local update = require "update"
update.boot("cab")
parallel.waitForAny(function() shell.run("cab") end, function() update.watch("cab") end)
