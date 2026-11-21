-- Door timing, reopen, and the 3-strike alarm.
package.path = "/?.lua;/?/init.lua;" .. package.path
local H = require "tests.harness"

local function openAt(w, car)
  w:door(car, "open")
  ccunit.truthy(w:runUntil(function() return w:doors(car) == "open" end, 5), "doors open")
end

ccunit.test("door-open restarts the minute; a hall call at the floor extends it", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  openAt(w, "A")
  w:run(40)
  w:door("A", "open") -- restarts the minute
  w:run(40)
  ccunit.eq(w:doors("A"), "open", "still open 80 s after opening")
  w:hall("G", "up") -- extends it again
  w:run(45)
  ccunit.eq(w:doors("A"), "open", "still open after the hall call")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 20))
end, { timeout = 15 })

ccunit.test("door-open while closing reopens", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  openAt(w, "A")
  w:door("A", "close")
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closing" end, 2))
  w:door("A", "open")
  w:run(0.2)
  ccunit.truthy(w:doors("A") == "opening" or w:doors("A") == "open", "reopens")
  w:run(30)
  ccunit.eq(w:doors("A"), "open", "with a fresh minute")
end, { timeout = 10 })

ccunit.test("a blocked doorway reopens and retries; 3 failed closes sound the alarm", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  openAt(w, "A")
  w.plant.cars.A.blocked = true
  local t0 = w.now
  w:door("A", "close")
  w:run(0.3)
  ccunit.eq(w:doors("A"), "open", "will not start closing on a player")
  -- the player steps in just as the doors start closing, three times
  for k = 1, 3 do
    w.plant.cars.A.blocked = false
    if w:doors("A") == "open" then w:door("A", "close") end
    ccunit.truthy(w:runUntil(function() return w:doors("A") == "closing" end, 10), "closing " .. k)
    w.plant.cars.A.blocked = true
    ccunit.truthy(w:runUntil(function() return w:doors("A") == "opening" or w:doors("A") == "open" end, 2), "reopens " .. k)
    ccunit.eq(w:car("A").door.strikes, k)
    if k < 3 then ccunit.eq(#w:messagesOf("alarm", "A", t0), 0, "no alarm yet") end
  end
  local al = w:messagesOf("alarm", "A", t0)
  ccunit.eq(#al, 1, "alarm after the third")
  ccunit.eq(al[1].on, true)
  -- the player moves away: it closes and the strikes reset
  w.plant.cars.A.blocked = false
  ccunit.truthy(w:runUntil(function() return w:doors("A") == "closed" end, 15))
  ccunit.eq(w:car("A").door.strikes, 0)
  w:run(12)
  local last = w:messagesOf("alarm", "A", t0)
  ccunit.eq(last[#last].on, false, "alarm stops")
end, { timeout = 15 })

ccunit.test("three door-open presses at one stop sound the alarm", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local t0 = w.now
  for _ = 1, 3 do w:door("A", "open"); w:run(1) end
  local al = w:messagesOf("alarm", "A", t0)
  ccunit.eq(#al, 1)
  ccunit.eq(al[1].on, true)
end, { timeout = 10 })

ccunit.test("a door that never reports closed keeps reopening and the car never moves", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  openAt(w, "A")
  w.plant.cars.A.doorJam = true
  w:call("A", "4")
  w:door("A", "close")
  w:run(40)
  ccunit.eq(w:car("A").moving, false)
  ccunit.eq(w:p("A").release, false)
  ccunit.truthy(w:car("A").door.strikes >= 3, "strikes " .. w:car("A").door.strikes)
  w.plant.cars.A.doorJam = false
  ccunit.truthy(w:arriveOpen("A", "4", 80), "goes once the door closes")
end, { timeout = 15 })

ccunit.test("the cab alarm button sounds the alarm", function()
  local w = H.world({ start = { A = "G", B = "6" } })
  local t0 = w.now
  w:alarmButton("A")
  w:run(0.2)
  ccunit.eq(w:messagesOf("alarm", "A", t0)[1].on, true)
  w:run(4)
  local l = w:messagesOf("alarm", "A", t0)
  ccunit.eq(l[#l].on, false)
end, { timeout = 10 })
