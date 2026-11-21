-- Inspection (maintenance) mode: manual slow up/down while held, calls ignored.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

ccunit.test("inspection: moves only while a button is held, slowly", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local p = w:p("A")
  p.inspect = true
  w:run(0.5)
  ccunit.eq(w:mode("A"), "inspection")
  ccunit.eq(w.ctl:indicator("A", 3).text, "Maintenance")
  w:call("A", "4")
  w:hall("G", "up")
  w:run(5)
  ccunit.eq(w:car("A").moving, false, "ignores calls")
  ccunit.eq(next(w:car("A").calls), nil)
  local y0 = w:y("A")
  p.inspectUp = true
  w:run(3)
  ccunit.truthy(w:car("A").moving)
  ccunit.eq(p.rpm, w.cfg.motion.inspectRpm)
  p.inspectUp = false
  w:run(0.2)
  ccunit.eq(p.release, false, "brake on release of the button")
  local y1 = w:y("A")
  ccunit.truthy(y1 > y0 + 0.5 and y1 < y0 + 1.2, "moved up slowly: " .. (y1 - y0))
  w:run(3)
  ccunit.near(w:y("A"), y1, 0.001)
  p.inspectDown = true
  w:run(2)
  p.inspectDown = false
  w:run(0.2)
  ccunit.truthy(w:y("A") < y1, "down")
  ccunit.eq(p.rpm, 0)
end, { timeout = 10 })

ccunit.test("inspection: doors close and must stay closed to move", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:door("A", "open")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "open" end, 5))
  w:p("A").inspect = true
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 10))
  w:p("A").doorSensor = "fail"
  w:p("A").inspectUp = true
  w:run(3)
  ccunit.eq(w:car("A").moving, false, "no move with a door sensor fault")
end, { timeout = 10 })

ccunit.test("switching inspection off: back to service, levels at the nearest floor", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local p = w:p("A")
  p.inspect = true; w:run(0.3)
  p.inspectUp = true; w:run(4); p.inspectUp = false; w:run(0.3)
  ccunit.truthy(w:car("A").atFloor == nil, "between floors")
  p.inspect = false
  ccunit.truthy(w:runUntil(function() return w:levelAt("A", "G") and w:doors("A") == "open" end, 30))
  ccunit.eq(w:mode("A"), "normal")
end, { timeout = 10 })
