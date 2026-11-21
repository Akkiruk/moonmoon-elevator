-- Screenshot helper: `shot normal|arriving|fire|ooo [floor]` draws both monitors with a sample hub message.
local landing = require "landing"
local mode, floor = ({ ... })[1] or "normal", ({ ... })[2] or "G"
landing.config.floor = floor
landing.send = function() end
local msgs = {
  normal = { car = "A", carFloor = "3", dir = "up", doors = "closed", up = true, down = false, mode = "normal" },
  arriving = { car = "B", carFloor = floor, dir = "down", lantern = "down", doors = "opening", up = false, down = true, mode = "normal" },
  fire = { car = "A", carFloor = "G", doors = "open", mode = "fire_recall" },
}
parallel.waitForAny(landing.run, function()
  sleep(0.3)
  if msgs[mode] then
    local m = { type = "landing", floor = floor }
    for k, v in pairs(msgs[mode]) do m[k] = v end
    os.queueEvent("rednet_message", 9, m, "mmlift")
  end
  sleep(0.5)
end)
