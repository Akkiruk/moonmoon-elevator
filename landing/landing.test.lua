-- Run from this folder: craftos-mcp test landing.test.lua
-- landing.send is replaceable so tests collect what would go to the hub. Hub messages and touches are real events.
-- Monitors: "left" is 2x1 (indicator, 36x10 at 0.5), "bottom" is 1x2 (call station, 15x24).
local landing = require "landing"

local sent
local function setup(floor, silence)
  sent = {}
  landing.config.floor = floor or "G"
  landing.config.silence = silence or 30
  landing.send = function(m) sent[#sent + 1] = m end
end

local function with(f) parallel.waitForAny(landing.run, function() f() end) end

local function feed(t)
  local m = { type = "landing", floor = landing.config.floor, car = "A", carFloor = "3", doors = "closed",
              up = false, down = false, mode = "normal" }
  for k, v in pairs(t or {}) do m[k] = v end
  os.queueEvent("rednet_message", 9, m, "mmlift")
  sleep(0.15)
end

local function rows(c)
  local o = {}
  for y = 1, c.h do
    local t = {}
    for x = 1, c.w do t[x] = c[y][x][1] end
    o[y] = table.concat(t)
  end
  return o
end

local function bgCount(c, y, x1, x2, col)
  local n = 0
  for x = x1, x2 do if c[y][x][3] == col then n = n + 1 end end
  return n
end

local function button(id)
  for _, b in ipairs(landing.stationLayout(15, 24)) do if b.id == id then return b end end
end

local function tap(id)
  local b = button(id)
  os.queueEvent("monitor_touch", "bottom", b.x1 + 3, b.y1 + 2)
  sleep(0.15)
end

local function btnBg(id) local b = button(id); return landing.staFrame[b.y1 + 3][b.x1 + 1][3] end

ccunit.test("monitors are found by size", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(landing.ind.name, "left")
  ccunit.eq(landing.ind.w, 36); ccunit.eq(landing.ind.h, 10)
  ccunit.eq(landing.sta.name, "bottom")
  ccunit.eq(landing.sta.w, 15); ccunit.eq(landing.sta.h, 24)
end, { timeout = 10 })

ccunit.test("hello at boot with the floor", function()
  setup("2")
  with(function() sleep(0.3) end)
  ccunit.eq(sent[1], { type = "hello", role = "landing", floor = "2" })
end, { timeout = 10 })

ccunit.test("indicator: car floor, arrow and car letter", function()
  setup()
  with(function()
    feed({ carFloor = "3", dir = "up", car = "B" })
    local c = landing.indFrame
    ccunit.contains(rows(c)[1], "CAR B")
    ccunit.eq(c[1][3][3], colors.gray)
    ccunit.eq(bgCount(c, 3, 1, 26, colors.white), 5, "the white 3")
    ccunit.eq(bgCount(c, 4, 27, 36, colors.lime), 3, "up arrow")
    ccunit.eq(bgCount(c, 6, 27, 36, colors.lime), 1)
    ccunit.contains(rows(c)[10], "FLOOR G")
    feed({ carFloor = "P1", dir = "down", doors = "open" })
    c = landing.indFrame
    ccunit.eq(bgCount(c, 6, 27, 36, colors.lime), 3, "down arrow")
    ccunit.contains(rows(c)[10], "DOORS OPEN")
    feed({ carFloor = "6", dir = nil })
    ccunit.eq(bgCount(landing.indFrame, 4, 27, 36, colors.lime), 0)
  end)
end, { timeout = 10 })

ccunit.test("indicator: arrival lantern lights up and down", function()
  setup()
  with(function()
    feed({ carFloor = "G", lantern = "up", dir = "up" })
    local c = landing.indFrame
    ccunit.contains(rows(c)[1], "ARRIVING")
    ccunit.truthy(bgCount(c, 5, 27, 36, colors.orange) >= 4)
    ccunit.eq(bgCount(c, 2, 26, 35, colors.yellow), 10, "lit top edge")
    local upTop = bgCount(c, 3, 27, 36, colors.black)  -- the dark arrow tip
    feed({ carFloor = "G", lantern = "down" })
    ccunit.neq(bgCount(landing.indFrame, 3, 27, 36, colors.black), upTop, "down lantern differs")
    feed({ carFloor = "G", lantern = nil, dir = nil })
    ccunit.eq(bgCount(landing.indFrame, 5, 27, 36, colors.orange), 0, "lantern off")
  end)
end, { timeout = 10 })

ccunit.test("indicator banners by mode", function()
  setup()
  with(function()
    feed({ mode = "fire_recall" })
    local c = landing.indFrame
    ccunit.contains(rows(c)[1], "FIRE SERVICE")
    ccunit.eq(c[1][2][3], colors.red)
    ccunit.eq(bgCount(c, 3, 1, 26, colors.red), 5, "red floor")
    feed({ mode = "inspection" })
    c = landing.indFrame
    ccunit.contains(rows(c)[1], "MAINTENANCE")
    ccunit.eq(c[1][2][3], colors.orange)
    feed({ mode = "normal", outOfOrder = true })
    c = landing.indFrame
    ccunit.contains(rows(c)[1], "OUT OF ORDER")
    ccunit.contains(rows(c)[9], "Out of Order")
    ccunit.eq(bgCount(c, 4, 27, 36, colors.lime), 0)
    feed({ mode = "normal" })
    ccunit.contains(rows(landing.indFrame)[1], "CAR A")
  end)
end, { timeout = 10 })

ccunit.test("call station: Up above Down in the middle floors", function()
  setup("G")
  with(function() feed() end)
  local up, down = button("up"), button("down")
  ccunit.truthy(up and down)
  ccunit.truthy(up.y2 < down.y1)
  ccunit.eq(#landing.buttons(), 2)
end, { timeout = 10 })

ccunit.test("top floor has only Down, bottom floor only Up", function()
  setup("6")
  with(function() feed() end)
  ccunit.eq(landing.buttons(), { "down" })
  ccunit.eq(#landing.stationLayout(15, 24), 1)
  ccunit.eq(landing.stationLayout(15, 24)[1].id, "down")
  setup("L1")
  with(function() feed() end)
  ccunit.eq(landing.buttons(), { "up" })
  ccunit.eq(landing.stationLayout(15, 24)[1].id, "up")
  -- and a touch on a floor with one button sends that one
  with(function()
    feed()
    local b = landing.stationLayout(15, 24)[1]
    os.queueEvent("monitor_touch", "bottom", b.x1 + 3, b.y1 + 2)
    sleep(0.2)
  end)
  ccunit.eq(sent[#sent], { type = "hall", floor = "L1", dir = "up" })
end, { timeout = 15 })

ccunit.test("touches send hall calls", function()
  setup("3")
  with(function()
    feed()
    sent = {}
    tap("up"); tap("down")
    ccunit.eq(sent[1], { type = "hall", floor = "3", dir = "up" })
    ccunit.eq(sent[2], { type = "hall", floor = "3", dir = "down" })
    os.queueEvent("monitor_touch", "bottom", 1, 12) -- between the buttons
    os.queueEvent("monitor_touch", "left", 5, 5)    -- the indicator is not a button
    sleep(0.2)
    ccunit.eq(#sent, 2)
  end)
end, { timeout = 10 })

ccunit.test("registered calls light their button", function()
  setup("3")
  with(function()
    feed({ up = true, down = false })
    ccunit.eq(btnBg("up"), colors.orange)
    ccunit.eq(btnBg("down"), colors.lightGray)
    feed({ up = false, down = true })
    ccunit.eq(btnBg("up"), colors.lightGray)
    ccunit.eq(btnBg("down"), colors.orange)
  end)
end, { timeout = 10 })

ccunit.test("dead in fire, inspection and out of order: dimmed, no messages", function()
  setup("3")
  with(function()
    for _, t in ipairs({ { mode = "fire_recall" }, { mode = "firefighter" }, { mode = "inspection" },
      { mode = "emergency" }, { outOfOrder = true } }) do
      t.up = true
      feed(t)
      ccunit.eq(btnBg("up"), colors.gray, (t.mode or "outOfOrder"))
      sent = {}
      tap("up")
      ccunit.eq(#sent, 0, "no message in " .. (t.mode or "outOfOrder"))
    end
    feed({ mode = "fire_recall" })
    ccunit.contains(rows(landing.staFrame)[1], "FIRE SERVICE")
    feed({ outOfOrder = true })
    ccunit.contains(rows(landing.staFrame)[1], "OUT OF ORDER")
    feed({ mode = "normal" })
    sent = {}
    tap("down")
    ccunit.eq(#sent, 1, "works again")
  end)
end, { timeout = 15 })

ccunit.test("lockdown mode alone does not kill the station (the hub flags outOfOrder)", function()
  setup("3")
  with(function()
    feed({ mode = "lockdown_trapped" })
    sent = {}
    tap("up")
    ccunit.eq(#sent, 1)
  end)
end, { timeout = 10 })

ccunit.test("hub silence: Out of Order on both monitors, then back", function()
  setup("3", 1)
  with(function()
    feed({ carFloor = "4", up = true })
    ccunit.contains(rows(landing.indFrame)[1], "CAR A")
    sleep(1.6)
    ccunit.contains(rows(landing.indFrame)[1], "OUT OF ORDER")
    ccunit.contains(rows(landing.staFrame)[1], "OUT OF ORDER")
    ccunit.eq(btnBg("up"), colors.gray)
    sent = {}
    tap("up")
    ccunit.eq(#sent, 0)
    feed({ carFloor = "4" })
    ccunit.contains(rows(landing.indFrame)[1], "CAR A")
    tap("up")
    ccunit.eq(#sent, 1)
  end)
end, { timeout = 15 })

ccunit.test("starts Out of Order if the hub never speaks", function()
  setup("3", 1)
  with(function() sleep(1.6) end)
  ccunit.contains(rows(landing.indFrame)[1], "OUT OF ORDER")
end, { timeout = 10 })

ccunit.test("messages for another floor are ignored", function()
  setup("3")
  with(function()
    feed({ carFloor = "4" })
    os.queueEvent("rednet_message", 9, { type = "landing", floor = "5", carFloor = "6", mode = "fire_recall" }, "mmlift")
    sleep(0.2)
    ccunit.contains(rows(landing.indFrame)[1], "CAR A")
    ccunit.eq(landing.view().carFloor, "4")
  end)
end, { timeout = 10 })

ccunit.test("a speaker, when there is one, chimes once as the lantern lights", function()
  setup("3")
  local notes = 0
  local realFind = peripheral.find
  peripheral.find = function(t, f)
    if t == "speaker" then return { playNote = function() notes = notes + 1; return true end } end
    return realFind(t, f)
  end
  with(function()
    feed({ lantern = "up" })
    feed({ lantern = "up" })
    feed({ lantern = nil })
    feed({ lantern = "down" })
  end)
  peripheral.find = realFind
  ccunit.eq(notes, 2)
end, { timeout = 10 })
