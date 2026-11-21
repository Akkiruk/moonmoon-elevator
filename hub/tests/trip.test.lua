-- A normal trip: accelerate, cruise, slow, level, stop within 1/16 block, chime, doors, close after the minute.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

ccunit.test("G to 6: smooth profile and a level stop", function()
  local w = H.world({ start = { A = "G", B = "P3" } })
  ccunit.eq(w:mode("A"), "normal")
  ccunit.eq(w:doors("A"), "closed")
  local t0 = w.now
  w:call("A", "6")
  ccunit.truthy(w:runUntil(function() return w:car("A").moving end, 2), "starts")
  -- brake released before the motor turns
  ccunit.truthy(w:runUntil(function() return w:p("A").rpm ~= 0 end, 2), "motor runs")
  ccunit.truthy(w:p("A").rpm > 0 and w:p("A").rpm < 20, "starts slowly, rpm=" .. w:p("A").rpm)
  ccunit.truthy(w:arriveOpen("A", "6", 60), "arrives at 6 with doors open")
  local p = w:p("A")
  ccunit.eq(p.maxRpm, w.cfg.motion.cruiseRpm, "reaches cruise")
  ccunit.truthy(math.abs(w:offset("A", "6")) <= 1 / 16, "level within 1/16: " .. w:offset("A", "6"))
  ccunit.eq(p.release, false, "braked at the floor")
  ccunit.eq(p.rpm, 0)
  -- the last stretch is at levelling speed, and the speed only falls during the slow-down
  local stopY = w.plant:stop("A", "6")
  local sawLevel = false
  for _, e in ipairs(p.log) do
    if e.t > t0 and e.rpm ~= 0 and stopY - e.y < 0.3 then
      ccunit.eq(e.rpm, w.cfg.motion.levelRpm, "creeps in at levelRpm")
      sawLevel = true
    end
  end
  ccunit.truthy(sawLevel, "levelled")
  -- top floor chimes twice
  local ch = w:messagesOf("chime", "A", t0)
  ccunit.eq(#ch, 1)
  ccunit.eq(ch[1].count, 2)
  -- landing door at 6 opens with the car door
  ccunit.eq(w.out.cars.A.doorOpen, true)
  ccunit.eq(w.out.cars.A.landing[11], true)
  -- the doors stay open for a minute, then close and the car waits
  local opened = w.now
  w:run(50)
  ccunit.eq(w:doors("A"), "open", "still open after 50 s")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 20), "closes")
  ccunit.truthy(w.now - opened >= 59, "after the minute")
  ccunit.eq(w.out.cars.A.landing[11], nil)
  w:run(5)
  ccunit.truthy(w:levelAt("A", "6"), "waits at its floor")
  ccunit.eq(w:state("A").dir, nil)
end, { timeout = 20 })

ccunit.test("down trip chimes twice, up once; bottom always once", function()
  local w = H.world({ start = { A = "4", B = "6" } })
  local t0 = w.now
  w:call("A", "P2")
  ccunit.truthy(w:arriveOpen("A", "P2", 60))
  ccunit.eq(w:messagesOf("chime", "A", t0)[1].count, 2)
  w:door("A", "close")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 10))
  t0 = w.now
  w:call("A", "3")
  ccunit.truthy(w:arriveOpen("A", "3", 60))
  ccunit.eq(w:messagesOf("chime", "A", t0)[1].count, 1)
  ccunit.truthy(math.abs(w:offset("A", "3")) <= 1 / 16)
  w:door("A", "close")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 10))
  t0 = w.now
  w:hall("L1", "up")
  ccunit.truthy(w:arriveOpen("A", "L1", 80) or w:arriveOpen("B", "L1", 80))
  local who = w:levelAt("A", "L1") and "A" or "B"
  ccunit.eq(w:messagesOf("chime", who, t0)[1].count, 1)
end, { timeout = 20 })

ccunit.test("state message for the cab", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:call("A", "3")
  w:run(3)
  local s = w:state("A")
  ccunit.eq(s.type, "state")
  ccunit.eq(s.mode, "normal")
  ccunit.eq(s.dir, "up")
  ccunit.eq(s.next, "3")
  ccunit.eq(s.doors, "closed")
  local pn = w.ctl:panelState("A")
  ccunit.eq(pn.lit["3"], true)
  ccunit.eq(pn.keycard_window, false)
end, { timeout = 10 })
