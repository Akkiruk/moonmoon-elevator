-- Inspection (maintenance) mode: manual slow up/down while held, calls ignored.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

ccunit.test("inspection: moves only while a button is held, slowly", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local p = w:p("A")
  p.inspect = true
  w:run(0.5)
  ccunit.eq(w:mode("A"), "inspection")
  ccunit.eq(w:landing("A", "P3").mode, "inspection", "landings show Maintenance")
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

-- the roof touch station, over rednet
local function jogFor(w, car, dir, seconds)
  local stop = w.now + seconds
  while w.now < stop do w:jog(car, dir); w:run(0.3) end
end

ccunit.test("roof station: on/off and a jog that is resent every 0.3 s", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:call("A", "4")
  w:inspect("A", true)
  w:run(0.2)
  ccunit.eq(w:mode("A"), "inspection")
  ccunit.eq(next(w:car("A").calls), nil, "queue cancelled")
  local y0 = w:y("A")
  jogFor(w, "A", "up", 3)
  ccunit.truthy(w:car("A").moving)
  ccunit.eq(w:p("A").rpm, w.cfg.motion.inspectRpm)
  w:jog("A", "stop")
  w:run(0.2)
  ccunit.eq(w:p("A").release, false, "stop brakes")
  ccunit.truthy(w:y("A") > y0 + 0.5)
  local y1 = w:y("A")
  jogFor(w, "A", "down", 2)
  w:jog("A", "stop"); w:run(0.2)
  ccunit.truthy(w:y("A") < y1, "down")
  w:inspect("A", false)
  w:run(0.2)
  ccunit.eq(w:mode("A"), "normal")
end, { timeout = 10 })

ccunit.test("roof station: dead-man stop when the jog stops coming", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:inspect("A", true)
  w:run(0.2)
  w:jog("A", "up")
  w:run(0.5)
  ccunit.truthy(w:car("A").moving, "moving after one jog")
  w:run(0.4) -- 0.9 s since the jog
  ccunit.eq(w:car("A").moving, false, "stopped")
  ccunit.eq(w:p("A").release, false, "braked")
  ccunit.eq(w:mode("A"), "inspection")
end, { timeout = 10 })

ccunit.test("roof station: no jog past the top stop", function()
  local w = H.world({ start = { A = "6", B = "G" } })
  w:inspect("A", true)
  w:run(0.2)
  jogFor(w, "A", "up", 3)
  ccunit.eq(w:car("A").moving, false)
  ccunit.truthy(w:y("A") <= w.plant:stop("A", "6") + 0.05)
end, { timeout = 10 })

ccunit.test("roof station: switching on is only honoured once the car stops", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:call("A", "4")
  ccunit.truthy(w:runUntil(function() return w:car("A").moving end, 3))
  w:run(1)
  w:inspect("A", true)
  w:run(0.2)
  ccunit.eq(w:mode("A"), "normal", "not while moving")
  ccunit.truthy(w:runUntil(function() return not w:car("A").moving end, 30))
  w:run(0.2)
  ccunit.eq(w:mode("A"), "inspection", "applied when it stops")
end, { timeout = 10 })
