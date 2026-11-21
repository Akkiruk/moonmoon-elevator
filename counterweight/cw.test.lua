-- Run from this folder: craftos-mcp test
local cw = require "cw"

local sent, y
local function setup()
  sent, y = {}, 90.5
  cw.hubId = nil
  cw.config.car = "A"
  cw.posSource = function() return y end
  cw.send = function(m) sent[#sent + 1] = m end
end

local function with(f)
  parallel.waitForAny(function() cw.run() end, f)
end

ccunit.test("reports its height about 5 times a second, nothing when GPS fails", function()
  setup()
  with(function()
    sleep(1.05)
    ccunit.truthy(#sent >= 4 and #sent <= 7, "count " .. #sent)
    ccunit.eq(sent[1].type, "cwpos"); ccunit.eq(sent[1].car, "A"); ccunit.eq(sent[1].y, 90.5)
    local n = #sent
    y = nil
    sleep(0.6)
    ccunit.eq(#sent, n, "no fix, no message")
  end)
end, { timeout = 10 })

ccunit.test("learns the hub from its car's state messages only", function()
  setup()
  with(function()
    os.queueEvent("rednet_message", 5, { type = "state", car = "B" }, "mmlift")
    os.queueEvent("rednet_message", 6, { type = "landing", car = "A" }, "mmlift")
    sleep(0.1)
    ccunit.eq(cw.hubId, nil)
    os.queueEvent("rednet_message", 9, { type = "state", car = "A" }, "mmlift")
    sleep(0.1)
    ccunit.eq(cw.hubId, 9)
  end)
end, { timeout = 10 })
