-- Fire service: Phase I recall to G, lock-out, reset only after the alarm clears, Phase II firefighter.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

local function recalled(w)
  return w:levelAt("A", "G") and w:levelAt("B", "G") and w:doors("A") == "open" and w:doors("B") == "open"
end

ccunit.test("Phase I: both cars to G, doors open, locked out", function()
  local w = H.world({ start = { A = "4", B = "P2" } })
  w:call("A", "6")
  w:call("B", "P3")
  w:hall("5", "down")
  w:run(2)
  ccunit.truthy(w:car("A").moving, "A moving up, away from G")
  w.plant.fire = true
  w:run(0.1)
  ccunit.eq(w:mode("A"), "fire_recall")
  ccunit.eq(w:mode("B"), "fire_recall")
  ccunit.eq(next(w:car("A").calls), nil, "queue cleared")
  ccunit.eq(w.ctl.hall.down[10], nil, "hall calls cleared")
  ccunit.eq(w:state("A").message, "Fire - returning to G")
  ccunit.truthy(w:runUntil(recalled, 60), "both at G with doors open")
  ccunit.eq(w:mode("A"), "fire_hold")
  ccunit.eq(w:landing("A", "4").mode, "fire_hold", "landings show Fire Service")
  ccunit.eq(w:landing("A", "4").outOfOrder, false)
  -- locked out: calls and door buttons do nothing, doors stay open
  w:call("A", "3")
  w:hall("2", "up")
  w:door("B", "close")
  w:run(90)
  ccunit.truthy(recalled(w), "still at G, doors open")
  ccunit.eq(w.ctl.hall.up[7], nil)
  local mus = w:messagesOf("music", "A")
  ccunit.eq(mus[#mus].cmd, "stop")
  -- the signal flickers off: still locked out until the reset
  w.plant.fire = false
  w:run(30)
  ccunit.eq(w:mode("A"), "fire_hold", "stays locked out after the alarm clears")
end, { timeout = 20 })

ccunit.test("reset only works once the alarm is off", function()
  local w = H.world({ start = { A = "G", B = "2" } })
  w.plant.fire = true
  ccunit.truthy(w:runUntil(recalled, 40))
  w.plant.fireReset = true; w:run(0.3); w.plant.fireReset = false; w:run(0.3)
  ccunit.eq(w:mode("A"), "fire_hold", "reset ignored while the alarm is on")
  w.plant.fire = false
  w:run(1)
  ccunit.eq(w:mode("A"), "fire_hold")
  w.plant.fireReset = true; w:run(0.3); w.plant.fireReset = false; w:run(0.3)
  ccunit.eq(w:mode("A"), "normal")
  ccunit.eq(w:mode("B"), "normal")
  ccunit.eq(w:doors("A"), "open", "doors stay open, normal dwell")
  w:call("A", "4")
  w:door("A", "close")
  ccunit.truthy(w:arriveOpen("A", "4", 60), "back in service")
end, { timeout = 15 })

ccunit.test("Phase II: the firefighter runs the car", function()
  local w = H.world({ start = { A = "3", B = "6" } })
  w.plant.fire = true
  ccunit.truthy(w:runUntil(recalled, 60))
  w.plant.cars.A.firefighter = true
  w:run(0.2)
  ccunit.eq(w:mode("A"), "firefighter")
  ccunit.eq(w.ctl:panelState("A").locked.P1, nil, "buttons live")
  ccunit.eq(w.ctl:panelState("B").locked.P1, true, "B still locked")
  w:call("A", "5")
  w:run(5)
  ccunit.eq(w:car("A").moving, false, "doors still open: the firefighter closes them")
  w:door("A", "close")
  ccunit.truthy(w:runUntil(function() return w:levelAt("A", "5") and not w:car("A").moving end, 60), "goes to 5")
  w:run(3)
  ccunit.eq(w:doors("A"), "closed", "doors do not open by themselves")
  w:door("A", "open")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "open" end, 5))
  w:run(90)
  ccunit.eq(w:doors("A"), "open", "and do not close by themselves")
  -- key off: back to Phase I recall
  w:door("A", "close")
  w:run(4)
  w.plant.cars.A.firefighter = false
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "fire_hold" and w:levelAt("A", "G") end, 60))
end, { timeout = 20 })

ccunit.test("Phase II key without a fire does nothing", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w.plant.cars.A.firefighter = true
  w:run(1)
  ccunit.eq(w:mode("A"), "normal")
end, { timeout = 10 })
