-- The shared hall call button between the two lifts: the landing program with no car set, so either car answers.
-- If it crashes it starts again a few seconds later, and the updater keeps checking for a fix the whole time.
local ok, update = pcall(require, "update")
if not ok and fs.exists("/update.prev.lua") then ok, update = pcall(dofile, "/update.prev.lua") end
if ok then pcall(update.boot, "hall") end

local function run()
  while true do
    shell.run("landing")
    -- only reached after a crash: a fix may already be waiting
    if ok then
      local fine, changed = pcall(update.run, "hall")
      if fine and changed then os.reboot() end
    end
    sleep(5)
  end
end

if ok then
  -- a broken updater only stops the checks, never the program
  parallel.waitForAny(run, function() pcall(update.watch, "hall"); while true do os.pullEvent("never") end end)
else
  run()
end
