-- Lab lockdown: L1 and L2 sealed; trapped cars, cars stopped in the lab zone, Out of Order signs.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

ccunit.test("L1/L2 cannot be reached; other floors work", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w.plant.lockdown = true
  w:run(0.2)
  w:keycard("A")
  w:call("A", "L1")
  w:hall("L2", "up")
  w:run(0.5)
  ccunit.eq(w:car("A").calls[1], nil, "keycard + L1 does nothing")
  ccunit.eq(w.ctl.hall.up[2], nil, "L2 hall call does nothing")
  ccunit.eq(w.ctl:panelState("A").keycard_window, false)
  ccunit.eq(w.ctl:panelState("A").locked.L1, true)
  ccunit.eq(w.ctl:panelState("A").locked.G, nil)
  w:call("A", "P3")
  ccunit.truthy(w:arriveOpen("A", "P3", 60), "P3 still works")
  w.plant.lockdown = false
  w:run(0.2)
  w:keycard("A")
  w:call("A", "L1")
  w:run(0.1)
  ccunit.eq(w:car("A").calls[1], true, "back to normal when the signal goes off")
end, { timeout = 15 })

ccunit.test("pending L1/L2 stops are cancelled; a car above P3 never goes below it", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:keycard("A")
  w:call("A", "L1")
  w:hall("L2", "up")
  w:run(0.2)
  ccunit.eq(w:car("A").calls[1], true)
  ccunit.truthy(w:runUntil(function() return w:car("A").moving and w:y("A") < w.plant:stop("A", "P1") end, 20))
  w.plant.lockdown = true
  w:run(0.2)
  ccunit.eq(w:car("A").calls[1], nil)
  ccunit.eq(w.ctl.hall.up[2], nil)
  local lowest = w:y("A")
  w:runUntil(function()
    if w:y("A") < lowest then lowest = w:y("A") end
    return w:still("A") and w:car("A").atFloor ~= nil and w:doors("A") == "open"
  end, 60)
  ccunit.truthy(lowest > w.plant:stop("A", "P3") - 0.5, "stayed above the lab zone, lowest " .. lowest)
  ccunit.eq(w:mode("A"), "normal")
  local f = w.cfg.floors[w:car("A").atFloor]
  ccunit.truthy(f == "P3" or f == "P2" or f == "P1", "stopped at " .. f)
end, { timeout = 15 })

ccunit.test("a car at L1 is trapped; its signs say Out of Order except on L1/L2", function()
  local w = H.world({ start = { A = "L1", B = "6" } })
  w:door("A", "open")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "open" end, 5))
  w.plant.lockdown = true
  w:run(0.2)
  ccunit.eq(w:mode("A"), "lockdown_trapped")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 10), "sealed")
  w:call("A", "G")
  w:hall("L1", "up")
  w:hall("G", "down")
  w:run(20)
  ccunit.truthy(w:levelAt("A", "L1"), "stays at L1")
  ccunit.eq(w:p("A").release, false)
  ccunit.eq(w:landing("A", "G").outOfOrder, true, "G sign")
  ccunit.eq(w:landing("A", "6").outOfOrder, true, "6 sign")
  ccunit.eq(w:landing("A", "L1").outOfOrder, false, "L1 sign keeps showing the car")
  ccunit.eq(w:landing("A", "L1").carFloor, "L1")
  ccunit.eq(w:landing("A", "L2").outOfOrder, false, "L2 sign too")
  ccunit.eq(w:landing("A", "L2").carFloor, "L1")
  ccunit.eq(w:landing("B", "G").outOfOrder, false, "car B normal")
  -- B answered the G call
  ccunit.truthy(w:levelAt("B", "G"), "B took the hall call")
  -- music stops in lockdown
  local mus = w:messagesOf("music", "A")
  ccunit.eq(mus[#mus].cmd, "stop")
  -- lockdown ends: back to service
  w.plant.lockdown = false
  w:run(0.3)
  ccunit.eq(w:mode("A"), "normal")
  w:call("A", "2")
  ccunit.truthy(w:arriveOpen("A", "2", 60))
end, { timeout = 20 })

ccunit.test("a car departing L2 stops where it is and clears its queue", function()
  local w = H.world({ start = { A = "L2", B = "6" } })
  w:call("A", "5")
  w:call("A", "P3")
  ccunit.truthy(w:runUntil(function() return w:y("A") > w.plant:stop("A", "L2") + 3 end, 20), "departing")
  w.plant.lockdown = true
  w:run(0.1)
  ccunit.eq(w:mode("A"), "out_of_order")
  local y = w:y("A")
  w:run(15)
  ccunit.truthy(math.abs(w:y("A") - y) < 0.2, "stopped where it was")
  ccunit.eq(w:p("A").release, false)
  ccunit.eq(next(w:car("A").calls), nil, "queue cleared")
  ccunit.eq(w:landing("A", "G").outOfOrder, true)
  ccunit.eq(w.out.cars.A.doorOpen, false)
  -- released: it goes to the nearest floor and lets people out
  w.plant.lockdown = false
  ccunit.truthy(w:runUntil(function() return w:still("A") and w:car("A").atFloor and w:doors("A") == "open" end, 60))
end, { timeout = 15 })

ccunit.test("a car coming down between P3 and L2 stops where it is", function()
  local w = H.world({ start = { A = "P1", B = "6" } })
  w:keycard("A")
  w:call("A", "L1")
  ccunit.truthy(w:runUntil(function() return w:y("A") < w.plant:stop("A", "P3") - 2 end, 30))
  w.plant.lockdown = true
  w:run(0.1)
  ccunit.eq(w:mode("A"), "out_of_order")
  local y = w:y("A")
  w:run(10)
  ccunit.truthy(math.abs(w:y("A") - y) < 0.2)
  ccunit.truthy(w:y("A") > w.plant:stop("A", "L2"), "between L2 and P3")
end, { timeout = 15 })
