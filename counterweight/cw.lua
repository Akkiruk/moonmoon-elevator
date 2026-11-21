-- Counterweight computer: rides on the counterweight with a wireless modem and tells the hub its height a few times
-- a second ({ type = "cwpos", car, y }). The hub steers the counterweight's motor from that; nothing else.
--
--   cw                     run it (startup.lua does this at boot)
--   local cw = require "cw"   in a test: returns the module without running it
local PROTO = "mmlift"
local M = { config = { car = nil, period = 0.2, gpsTimeout = 0.15 } }

function M.posSource()
  local _, y = gps.locate(M.config.gpsTimeout)
  return y
end

-- straight to the hub once it has been heard from, like the cab
function M.send(msg)
  pcall(function()
    if M.hubId then rednet.send(M.hubId, msg, PROTO) else rednet.broadcast(msg, PROTO) end
  end)
end

local function netLoop()
  while true do
    local _, from, msg, proto = os.pullEvent("rednet_message")
    if proto == PROTO and type(msg) == "table" and msg.type == "state" and msg.car == M.config.car then M.hubId = from end
  end
end

local function posLoop()
  while true do
    local ok, y = pcall(M.posSource)
    if ok and y then M.send({ type = "cwpos", car = M.config.car, y = y }) end
    sleep(M.config.period)
  end
end

function M.run()
  local c = M.config
  c.car = c.car or settings.get("mmlift.car")
  if not c.car and fs.exists("/car.txt") then
    local f = fs.open("/car.txt", "r"); c.car = (f.readLine() or ""):match("%S+"); f.close()
  end
  c.car = c.car or "A"
  peripheral.find("modem", function(n, m) if m.isWireless() and not rednet.isOpen(n) then rednet.open(n) end end)
  parallel.waitForAny(netLoop, posLoop)
end

if select("#", ...) > 0 and (...) == "cw" then return M end
M.run()
