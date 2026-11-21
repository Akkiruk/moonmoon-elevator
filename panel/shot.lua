-- Screenshot helper: `shot` draws the panel with a sample hub message.
local panel = require "panel"
panel.config.car = "A"
panel.send = function() end
panel.cardInput = function() return false end
local mode = ({ ... })[1] or "normal"
local msgs = {
  normal = { lit = { ["3"] = true, G = true }, locked = {}, keycard_window = false, mode = "normal" },
  card = { lit = { L2 = true, ["5"] = true }, locked = {}, keycard_window = true, mode = "normal" },
  fire = { lit = {}, locked = { ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, P1 = true, P2 = true, P3 = true, L1 = true, L2 = true }, keycard_window = false, mode = "fire_recall" },
  ooo = nil,
}
parallel.waitForAny(panel.run, function()
  sleep(0.3)
  if msgs[mode] then
    local m = { type = "panel", car = "A" }
    for k, v in pairs(msgs[mode]) do m[k] = v end
    os.queueEvent("rednet_message", 9, m, "mmlift")
  end
  sleep(0.5)
end)
