-- Runs inspect. If it crashes it starts again a few seconds later, and the updater keeps checking for a fix
-- the whole time, so a bad push can always be fixed with another push.
local ok, update = pcall(require, "update")
if not ok and fs.exists("/update.prev.lua") then ok, update = pcall(dofile, "/update.prev.lua") end
if ok then pcall(update.boot, "inspect") end

local function run()
  while true do
    shell.run("inspect")
    -- only reached after a crash: a fix may already be waiting
    if ok then
      local fine, changed = pcall(update.run, "inspect")
      if fine and changed then os.reboot() end
    end
    sleep(5)
  end
end

if ok then
  -- a broken updater only stops the checks, never the program
  parallel.waitForAny(run, function() pcall(update.watch, "inspect"); while true do os.pullEvent("never") end end)
else
  run()
end
