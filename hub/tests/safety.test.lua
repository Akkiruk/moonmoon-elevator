-- Speed governor, cable failure, lost GPS and the floor-contact cross-check.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

local function cruising(w, car, to)
  w:call(car, to)
  ccunit.truthy(w:runUntil(function() return math.abs(w:p(car).rpm) == w.cfg.motion.cruiseRpm end, 20), "cruising")
end

local function braked(w, car)
  ccunit.eq(w:p(car).release, false, "brake dropped")
  ccunit.eq(w:p(car).rpm, 0, "motor stopped")
end

ccunit.test("governor: running down too fast trips emergency", function()
  local w = H.world({ start = { A = "6", B = "G" } })
  cruising(w, "A", "P3")
  w:p("A").overspeed = 1.8
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 1.5), "trips")
  braked(w, "A")
  w:p("A").overspeed = 1
  ccunit.eq(w:state("A").reason, "Overspeed")
  ccunit.eq(w:state("A").message, "Emergency - help is on the way")
  local mus = w:messagesOf("music", "A")
  ccunit.eq(mus[#mus].cmd, "stop")
  -- stays latched; calls refused; panel reset puts it back
  w:call("A", "G")
  w:run(10)
  ccunit.eq(w:mode("A"), "emergency")
  w:reset("A")
  w:run(0.2)
  ccunit.eq(w:mode("A"), "normal")
  ccunit.truthy(w:runUntil(function() return w:still("A") and w:car("A").atFloor and w:doors("A") == "open" end, 30),
    "rescue run to the nearest floor")
end, { timeout = 15 })

ccunit.test("cable failure while cruising up: brake and emergency", function()
  local w = H.world({ start = { A = "P3", B = "6" } })
  cruising(w, "A", "6")
  w:p("A").cableBroken = true
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 2), "detected within two seconds")
  braked(w, "A")
  ccunit.eq(w:state("A").reason, "Cable failure")
end, { timeout = 10 })

ccunit.test("cable failure while parked", function()
  local w = H.world({ start = { A = "4", B = "6" } })
  w:p("A").cableBroken = true
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 1.5))
  braked(w, "A")
end, { timeout = 10 })

ccunit.test("brake slips while parked (car rises): overspeed", function()
  local w = H.world({ start = { A = "4", B = "6" } })
  w:p("A").brakeFails = true
  w:p("A").overspeed = 0 -- nothing drives it; a slipping brake lets the counterweight pull it up
  w:p("A").cableBroken = false
  -- simulate the drift: push the car up by hand
  for _ = 1, 40 do w:p("A").y = w:p("A").y + 0.05; w:step() end
  ccunit.eq(w:mode("A"), "emergency")
end, { timeout = 10 })

ccunit.test("a jammed car stalls instead of paying out rope", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  cruising(w, "A", "6")
  w:p("A").jammed = true
  w:run(6)
  ccunit.eq(w:mode("A"), "normal", "a few seconds stuck is normal while the rope takes up its stretch")
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 4))
  ccunit.eq(w:state("A").reason, "Stalled")
  braked(w, "A")
end, { timeout = 10 })

ccunit.test("frozen GPS while moving is a stall", function()
  local w = H.world({ start = { A = "6", B = "G" } })
  for i = 1, #w.cfg.floors do w:p("A").noContact[i] = true end -- as built: no floor contacts, GPS only
  cruising(w, "A", "P3")
  w:p("A").gps = "frozen"
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 10))
  ccunit.eq(w:state("A").reason, "Stalled")
  braked(w, "A")
end, { timeout = 10 })

ccunit.test("rope surges and bounces don't trip anything", function()
  local w = H.world({ start = { A = "P3", B = "G" } })
  cruising(w, "A", "6")
  local p = w:p("A")
  p.kick = { v = -5, untilT = w.plant.now + 0.6 }  -- springs back down for a moment
  w:run(1.5)
  p.kick = { v = 10, untilT = w.plant.now + 1.3 }  -- then surges up
  w:run(2)
  ccunit.eq(w:mode("A"), "normal")
  ccunit.truthy(w:arriveOpen("A", "6", 60))
  w:door("A", "close")
  w:call("A", "P3")
  ccunit.truthy(w:runUntil(function() return math.abs(w:p("A").rpm) == w.cfg.motion.cruiseRpm end, 20))
  p.kick = { v = -3, untilT = w.plant.now + 0.3 }  -- a short spike going down
  w:run(1)
  ccunit.eq(w:mode("A"), "normal")
  ccunit.truthy(w:arriveOpen("A", "P3", 60))
end, { timeout = 15 })

ccunit.test("lost GPS while moving: brake, emergency", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  cruising(w, "A", "6")
  w:p("A").gps = "silent"
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 1), "within the 0.5 s limit")
  braked(w, "A")
  ccunit.eq(w:state("A").reason, "Lost position")
end, { timeout = 10 })

local function loseGpsOnTheWay(w, to)
  w:door("A", "close")
  w:call("A", to)
  ccunit.truthy(w:runUntil(function() return w:p("A").release and math.abs(w:p("A").rpm) >= 32 end, 40),
    "moving to " .. to .. " from y " .. w:y("A") .. " mode " .. w:mode("A") .. " doors " .. w:doors("A"))
  w:p("A").gps = "silent"
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 2), "tripped")
  w:p("A").gps = "ok"
end

ccunit.test("an emergency clears itself once the car stands still with a good position, then it levels", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  loseGpsOnTheWay(w, "6")
  w:run(15)
  ccunit.eq(w:mode("A"), "emergency", "not straight away")
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "normal" end, 15), "cleared by itself")
  ccunit.truthy(w:runUntil(function() return w:still("A") and w:car("A").atFloor and w:doors("A") == "open" end, 40),
    "levelled at a floor with the doors open")
end, { timeout = 15 })

ccunit.test("the fourth emergency in ten minutes waits for a person", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local function far() return w:y("A") > 116 and "G" or "6" end
  for n = 1, 3 do
    loseGpsOnTheWay(w, far())
    ccunit.truthy(w:runUntil(function() return w:mode("A") == "normal" end, 40), "auto reset " .. n)
    ccunit.truthy(w:runUntil(function() return w:still("A") and w:car("A").atFloor and w:doors("A") == "open" end, 60))
  end
  loseGpsOnTheWay(w, far())
  w:run(90)
  ccunit.eq(w:mode("A"), "emergency", "stays stopped")
  w:reset("A")
  w:run(0.2)
  ccunit.eq(w:mode("A"), "normal", "a person can still reset it")
end, { timeout = 30 })

ccunit.test("GPS fails (nogps) while parked: out of service, back when it returns", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:p("A").gps = "nogps"
  w:run(1)
  ccunit.eq(w:mode("A"), "out_of_order")
  ccunit.eq(w:state("A").reason, "No position")
  w:call("A", "3")
  w:run(3)
  ccunit.eq(w:p("A").release, false)
  w:hall("2", "up")
  w:run(0.3)
  ccunit.eq(w.ctl.hall.up[7], "B", "hall calls go to B")
  ccunit.eq(w:car("A").calls[8], nil, "car calls refused while out of service")
  w:p("A").gps = "ok"
  w:run(0.5)
  ccunit.eq(w:mode("A"), "normal")
  w:call("A", "3")
  ccunit.truthy(w:arriveOpen("A", "3", 60))
end, { timeout = 15 })

ccunit.test("passing a floor without its contact lighting is a fault", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:p("A").deadContacts[8] = true -- floor 3
  w:call("A", "5")
  ccunit.truthy(w:runUntil(function() return w:mode("A") == "emergency" end, 30))
  ccunit.eq(w:state("A").reason, "Contact 3 missed")
  braked(w, "A")
  ccunit.truthy(w:y("A") > w.plant:stop("A", "3") and w:y("A") < w.plant:stop("A", "3") + 2, "caught just past 3")
end, { timeout = 10 })

ccunit.test("a contact lit far from the GPS height is a fault", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  w:p("A").stuckContacts[11] = true
  w:run(0.5)
  ccunit.eq(w:mode("A"), "emergency")
  ccunit.eq(w:state("A").reason, "Contact 6 lit away from car")
end, { timeout = 10 })

ccunit.test("a normal run past every floor raises no contact fault", function()
  local w = H.world({ start = { A = "L1", B = "6" } })
  w:keycard("A")
  w:door("A", "close")
  w:call("A", "6")
  ccunit.truthy(w:arriveOpen("A", "6", 90))
  ccunit.eq(w:mode("A"), "normal")
  w:door("A", "close")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 10))
  w:keycard("A")
  w:call("A", "L1")
  ccunit.truthy(w:arriveOpen("A", "L1", 90))
  ccunit.eq(w:mode("A"), "normal")
end, { timeout = 15 })
