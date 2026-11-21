-- Two cars: hall calls go to the closer car; a car serves stops in its direction of travel, then reverses.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

ccunit.test("hall calls go to the closer car", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:hall("5", "down")
  w:run(0.2)
  ccunit.eq(w.ctl.hall.down[10], "B", "5 down -> B (at 6)")
  w:hall("P1", "up")
  w:run(0.2)
  ccunit.eq(w.ctl.hall.up[5], "A", "P1 up -> A (at G)")
  ccunit.truthy(w:arriveOpen("B", "5", 40), "B answers 5")
  ccunit.truthy(w:arriveOpen("A", "P1", 40), "A answers P1")
  ccunit.eq(w.ctl.hall.down[10], nil, "5 down cleared")
  ccunit.eq(w.ctl.hall.up[5], nil, "P1 up cleared")
  ccunit.eq(w.out.hallUpLit[5], false)
end, { timeout = 20 })

ccunit.test("collects in the direction of travel, then reverses", function()
  local w = H.world({ start = { A = "G", B = "L1" } })
  w.plant.cars.B.gps = "silent" -- B out of the way (no position: out of service)
  w:run(1)
  ccunit.eq(w:mode("B"), "out_of_order")
  w:call("A", "6")
  w:run(2)
  ccunit.truthy(w:car("A").moving)
  w:hall("3", "up")   -- on the way, same direction: served on the way up
  w:hall("4", "down") -- on the way, other direction: served after 6
  w:hall("P2", "up")  -- behind: served last
  local order = {}
  local last
  w:runUntil(function()
    local c = w:car("A")
    if c.atFloor and not c.moving and w:doors("A") == "opening" and c.atFloor ~= last then
      last = c.atFloor
      order[#order + 1] = w.cfg.floors[c.atFloor]
      w:door("A", "close")
    elseif w:doors("A") == "open" then
      w:door("A", "close")
    end
    return #order >= 4
  end, 200)
  ccunit.eq(order, { "3", "6", "4", "P2" })
end, { timeout = 30 })

ccunit.test("a lone car takes every call; an idle car at the floor opens at once", function()
  local w = H.world({ start = { A = "G", B = "2" } })
  local t0 = w.now
  w:hall("2", "up")
  w:run(0.5)
  ccunit.eq(w.ctl.hall.up[7], nil, "answered at once by B, not queued")
  ccunit.truthy(w:runUntil(function() return w:doors("B") == "open" end, 5))
  ccunit.eq(#w:messagesOf("chime", "B", t0), 1)
  ccunit.eq(w:car("A").moving, false, "A stays")
end, { timeout = 10 })

ccunit.test("calls move to the other car when one leaves service", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:hall("2", "up")
  w:run(0.2)
  ccunit.eq(w.ctl.hall.up[7], "A")
  w.plant.cars.A.inspect = true
  w:run(0.5)
  ccunit.eq(w:mode("A"), "inspection")
  ccunit.eq(w.ctl.hall.up[7], "B", "reassigned to B")
  ccunit.truthy(w:arriveOpen("B", "2", 40))
end, { timeout = 15 })
