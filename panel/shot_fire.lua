local panel = require "panel"
panel.config.car = "A"
panel.send = function() end
panel.cardInput = function() return false end
local on = ({ ... })[1] == "on"
parallel.waitForAny(panel.run, function()
  sleep(0.3)
  os.queueEvent("rednet_message", 9, { type = "panel", car = "A", lit = {}, locked = {}, keycard_window = true,
    mode = on and "firefighter" or "fire_hold", firefighter = on, fireKeyAllowed = not on }, "mmlift")
  sleep(0.6)
end)
