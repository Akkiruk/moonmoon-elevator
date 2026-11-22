-- Check for an update, then run the landing with the updater watching in the background.
local update = require "update"
update.boot("landing")
parallel.waitForAny(function() shell.run("landing") end, function() update.watch("landing") end)
