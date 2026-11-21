-- Interlock: never move unless the door reads closed. A failed or silent door sensor counts as open.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

local function neverMoves(w, car, seconds)
  local moved = false
  local stop = w.now + seconds
  while w.now < stop do
    w:step()
    if w:p(car).release or w:p(car).rpm ~= 0 then moved = true end
  end
  return not moved
end

ccunit.test("sensor fault (ok = false): the car refuses to move", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w.plant.cars.A.doorSensor = "fail"
  w:call("A", "4")
  ccunit.truthy(neverMoves(w, "A", 20), "brake never released")
  ccunit.eq(w:mode("A"), "out_of_order")
  ccunit.eq(w:state("A").reason, "Door sensor fault")
  ccunit.eq(w.ctl:indicator("A", 6).text, "Out of Order")
  -- sensor back: it carries on
  w.plant.cars.A.doorSensor = "ok"
  ccunit.truthy(w:arriveOpen("A", "4", 40), "goes once the sensor works")
end, { timeout = 15 })

ccunit.test("no door state from the cab counts as open", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w.plant.cars.A.doorSensor = "silent"
  w:run(4) -- the last report goes stale (2.5 s), then 1 s more makes it a fault
  ccunit.eq(w:mode("A"), "out_of_order")
  w:call("A", "2")
  ccunit.truthy(neverMoves(w, "A", 15))
  ccunit.eq(w:mode("A"), "out_of_order")
end, { timeout = 10 })

ccunit.test("a hall call skips a car with a door fault", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w.plant.cars.A.doorSensor = "fail"
  w:run(2)
  w:hall("2", "up")
  w:run(0.3)
  ccunit.eq(w.ctl.hall.up[7], "B")
end, { timeout = 10 })

ccunit.test("door reads open during travel: brake at once, wait", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:call("A", "6")
  ccunit.truthy(w:runUntil(function() return math.abs(w:p("A").rpm) == w.cfg.motion.cruiseRpm end, 20))
  -- the door is forced open (block state says open)
  w.plant.cars.A.doorOpen = true
  w.plant.cars.A.doorJam = true
  w:run(0.2)
  ccunit.eq(w:p("A").release, false, "braked")
  ccunit.eq(w:p("A").rpm, 0)
  ccunit.truthy(neverMoves(w, "A", 5), "stays put while the door reads open")
  ccunit.eq(w.out.cars.A.doorOpen, false, "and does not open a door between floors")
  w.plant.cars.A.doorJam = false
  ccunit.truthy(w:arriveOpen("A", "6", 60), "continues once closed")
end, { timeout = 15 })
