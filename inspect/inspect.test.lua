-- Run from this folder: craftos-mcp test inspect.test.lua
-- inspect.send is replaceable so tests collect messages. Hub states and touches are real events on the 1x1 monitor.
local inspect = require "inspect"

local sent
local function setup(silence)
  sent = {}
  inspect.config.car = "A"
  inspect.config.silence = silence or 30
  inspect.send = function(m) m.at = os.clock(); sent[#sent + 1] = m end
end

local function with(f) parallel.waitForAny(inspect.run, function() f() end) end

local function state(mode, floor)
  os.queueEvent("rednet_message", 9, { type = "state", car = "A", mode = mode or "normal", floor = floor or "4" }, "mmlift")
  sleep(0.15)
end

local function zone(id)
  for _, z in ipairs(inspect.zones(inspect.size[1], inspect.size[2])) do if z.id == id then return z end end
end

local function tap(id)
  local z = zone(id)
  os.queueEvent("monitor_touch", "front", z.x1 + 1, z.y1 + 1)
  sleep(0.15)
end

local function ofType(t)
  local o = {}
  for _, m in ipairs(sent) do if m.type == t then o[#o + 1] = m end end
  return o
end

local function rowText(y)
  local t = {}
  for x = 1, inspect.size[1] do t[x] = inspect.frame[y][x][1] end
  return table.concat(t)
end

local function bgAt(id) local z = zone(id); return inspect.frame[z.y1][z.x1][3] end

ccunit.test("1x1 monitor at scale 0.5 is 15x10 and the zones fit", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(inspect.size, { 15, 10 })
  for _, z in ipairs(inspect.zones(15, 10)) do
    ccunit.truthy(z.x1 >= 1 and z.x2 <= 15 and z.y1 >= 3 and z.y2 <= 10, z.id)
  end
  ccunit.truthy(zone("up").x2 < zone("down").x1)
end, { timeout = 10 })

ccunit.test("hello at boot", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(sent[1].type, "hello")
  ccunit.eq(sent[1].role, "inspect")
  ccunit.eq(sent[1].car, "A")
end, { timeout = 10 })

ccunit.test("state shows mode and floor at the top", function()
  setup()
  with(function()
    state("normal", "4")
    ccunit.contains(rowText(1), "NORMAL")
    ccunit.contains(rowText(2), "CAR A")
    ccunit.contains(rowText(2), "FL 4")
    ccunit.eq(inspect.frame[1][2][3], colors.gray)
    state("inspection", "G")
    ccunit.contains(rowText(1), "INSPECTION")
    ccunit.eq(inspect.frame[1][2][3], colors.orange)
    ccunit.contains(rowText(2), "FL G")
    state("fire_recall")
    ccunit.eq(inspect.frame[1][2][3], colors.red)
  end)
end, { timeout = 10 })

ccunit.test("INSPECT toggles and sends on/off; amber when on", function()
  setup()
  with(function()
    state("normal")
    ccunit.eq(bgAt("inspect"), colors.gray)
    tap("inspect")
    ccunit.eq(sent[#sent], { type = "inspect", car = "A", on = true, at = sent[#sent].at })
    ccunit.eq(bgAt("inspect"), colors.orange)
    ccunit.contains(rowText(zone("inspect").y1 + 2), "ON")
    state("inspection")  -- the hub agrees
    ccunit.eq(bgAt("inspect"), colors.orange)
    tap("inspect")
    ccunit.eq(sent[#sent].on, false)
    ccunit.eq(bgAt("inspect"), colors.gray)
    ccunit.eq(#ofType("inspect"), 2)
  end)
end, { timeout = 15 })

ccunit.test("the display follows the hub once its answer arrives", function()
  setup()
  inspect.config.grace = 0.3
  with(function()
    state("normal")
    tap("inspect")
    sleep(0.5)
    state("normal")             -- the hub refused
    ccunit.eq(bgAt("inspect"), colors.gray)
    state("inspection")         -- someone else switched it on
    ccunit.eq(bgAt("inspect"), colors.orange)
  end)
  inspect.config.grace = 1.5
end, { timeout = 10 })

ccunit.test("no moves unless inspection is on", function()
  setup()
  with(function()
    state("normal")
    tap("up"); tap("down")
    sleep(0.5)
    ccunit.eq(#ofType("inspect_move"), 0)
    tap("inspect")
    tap("up")
    ccunit.eq(#ofType("inspect_move"), 1)
  end)
end, { timeout = 10 })

ccunit.test("a jog sends at once, then every 0.3 s, and stops on the same arrow", function()
  setup()
  with(function()
    state("normal"); tap("inspect"); state("inspection")
    sent = {}
    tap("up")
    local first = ofType("inspect_move")
    ccunit.eq(#first, 1)
    ccunit.eq(first[1].dir, "up")
    ccunit.eq(first[1].car, "A")
    ccunit.eq(bgAt("up"), colors.lime)
    sleep(1.8)
    local moves = ofType("inspect_move")
    ccunit.truthy(#moves >= 6 and #moves <= 8, "count " .. #moves)
    for i = 2, #moves do
      local gap = moves[i].at - moves[i - 1].at
      ccunit.truthy(gap > 0.25 and gap < 0.4, "gap " .. gap)
    end
    tap("up")
    local last = ofType("inspect_move"); last = last[#last]
    ccunit.eq(last.dir, "stop")
    local n = #ofType("inspect_move")
    sleep(1)
    ccunit.eq(#ofType("inspect_move"), n, "nothing more after the stop")
    ccunit.eq(bgAt("up"), colors.lightGray)
  end)
end, { timeout = 15 })

ccunit.test("any other zone stops a jog", function()
  setup()
  with(function()
    state("normal"); tap("inspect"); state("inspection")
    tap("up")
    tap("down")
    local m = ofType("inspect_move")
    ccunit.eq(m[#m].dir, "stop", "the other arrow stops, it does not reverse")
    ccunit.eq(m[#m - 1].dir, "up")
    local n = #m
    sleep(0.8)
    ccunit.eq(#ofType("inspect_move"), n)
    tap("down")  -- a fresh jog down, then INSPECT ends it and switches off
    tap("inspect")
    m = ofType("inspect_move")
    ccunit.eq(m[#m].dir, "stop")
    ccunit.eq(sent[#sent].type, "inspect")
    ccunit.eq(sent[#sent].on, false)
  end)
end, { timeout = 15 })

ccunit.test("a jog stops when the hub leaves inspection", function()
  setup()
  with(function()
    state("normal"); tap("inspect"); state("inspection")
    tap("down")
    sleep(1.7) -- past the grace after the toggle, so the hub's word counts
    state("normal")
    local m = ofType("inspect_move"); m = m[#m]
    ccunit.eq(m.dir, "stop")
  end)
end, { timeout = 10 })

ccunit.test("no hub: 'No hub', jog stops, touches send nothing; a state restores it", function()
  setup(1.5)
  with(function()
    state("normal"); tap("inspect"); state("inspection")
    tap("up")
    sleep(2)
    ccunit.contains(rowText(1), "NO HUB")
    ccunit.eq(inspect.frame[1][2][3], colors.red)
    local m = ofType("inspect_move"); m = m[#m]
    ccunit.eq(m.dir, "stop")
    local n = #sent
    tap("inspect"); tap("up")
    sleep(0.5)
    ccunit.eq(#sent, n, "nothing sent without a hub")
    ccunit.eq(bgAt("inspect"), colors.gray)
    state("normal")
    ccunit.contains(rowText(1), "NORMAL")
  end)
end, { timeout = 15 })

ccunit.test("states for another car are ignored", function()
  setup()
  with(function()
    state("normal", "4")
    os.queueEvent("rednet_message", 9, { type = "state", car = "B", mode = "fire_recall", floor = "9" }, "mmlift")
    sleep(0.2)
    ccunit.contains(rowText(1), "NORMAL")
    ccunit.contains(rowText(2), "FL 4")
  end)
end, { timeout = 10 })
