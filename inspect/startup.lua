-- Check for an update, then run the inspect with the updater watching in the background.
local update = require "update"
update.boot("inspect")
parallel.waitForAny(function() shell.run("inspect") end, function() update.watch("inspect") end)
