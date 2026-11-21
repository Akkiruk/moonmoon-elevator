-- Screenshot helper: `shot normal|fire|inspection|ooo` runs the cab with a fixed state (positions are faked).
-- craftos-mcp run shot.lua normal --screenshot ../screenshots/cab-normal.png
local cab = require "cab"
local mode = ({ ... })[1] or "normal"
cab.config.car = "A"
cab.posSource = function() return 107.5 end
cab.send = function() end
local states = {
  normal = { floor = "G", dir = "up", doors = "closing", mode = "normal", next = "4", message = "Doors closing" },
  fire = { floor = "G", doors = "open", mode = "fire_recall", message = "Fire - exit at G" },
  inspection = { floor = "3", dir = "down", doors = "closed", mode = "inspection", message = "Maintenance" },
  ooo = nil,
}
parallel.waitForAny(cab.run, function()
  sleep(0.3)
  if states[mode] then
    local s = { type = "state", car = "A" }
    for k, v in pairs(states[mode]) do s[k] = v end
    os.queueEvent("rednet_message", 9, s, "mmlift")
  end
  sleep(0.5)
end)
