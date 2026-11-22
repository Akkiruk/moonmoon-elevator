-- Runs hub.lua. If it crashes it starts again a few seconds later, and the updater keeps checking for a fix
-- the whole time, so a bad push can always be fixed with another push.
local function brakes() pcall(function() require("hw").new(require("config")):safeStop() end) end
brakes() -- before anything slow, so a car can't keep moving while this boots
local ok, update = pcall(require, "update")
if not ok and fs.exists("/update.prev.lua") then ok, update = pcall(dofile, "/update.prev.lua") end
if ok then pcall(update.boot, "hub") end

local function run()
  while true do
    shell.run("hub.lua")
    brakes()
    -- only reached after a crash: a fix may already be waiting
    if ok then
      local fine, changed = pcall(update.run, "hub")
      if fine and changed then os.reboot() end
    end
    sleep(5)
  end
end

if ok then
  -- a broken updater only stops the checks, never the program
  parallel.waitForAny(run, function() pcall(update.watch, "hub"); while true do os.pullEvent("never") end end)
else
  run()
end
