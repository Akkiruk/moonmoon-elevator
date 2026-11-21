-- Run from this folder: craftos-mcp test plaque.test.lua
local plaque = require "plaque"

local function lines(c)
  local out = {}
  for y = 1, c.h do
    local t = {}
    for x = 1, c.w do t[x] = c[y][x][1] end
    out[y] = table.concat(t)
  end
  return out
end

ccunit.test("default plaque has every required line", function()
  local l = lines(plaque.render(36, 24, { car = "A" }))
  for _, s in ipairs({ "M O O N L I F T", "ELEVATOR CO.", "MODEL ML-11 TRACTION", "C A R   A", "RATED LOAD", "1600 kg / 21 pers.",
    "RATED SPEED", "2.5 m/s", "SERIAL NO.", "ML11-A-00417", "INSPECTED", "2026-11-20", "NEXT DUE", "2027-05-20",
    "IN CASE OF FIRE", "USE STAIRS" }) do
    ccunit.contains(l, s)
  end
end)

ccunit.test("the car letter and serial follow the car", function()
  local l = lines(plaque.render(36, 24, { car = "B" }))
  ccunit.contains(l, "C A R   B")
  ccunit.contains(l, "ML11-B-00417")
end)

ccunit.test("settings override fields; the fire notice is red", function()
  local c = plaque.render(36, 24, { car = "A", overrides = { serial = "X-1", load_kg = 1000, persons = 13 } })
  local l = lines(c)
  ccunit.contains(l, "X-1")
  ccunit.contains(l, "1000 kg / 13 pers.")
  local fireRow
  for y, s in ipairs(l) do if s:find("USE STAIRS", 1, true) then fireRow = y end end
  ccunit.eq(c[fireRow][18][2], colors.red)
end)

ccunit.test("a small monitor drops the inspection dates but keeps the rest", function()
  local l = lines(plaque.render(36, 14, { car = "A" }))
  for _, s in ipairs(l) do ccunit.eq(s:find("INSPECTED", 1, true), nil) end
  ccunit.contains(l, "RATED LOAD")
  ccunit.contains(l, "USE STAIRS")
end)

ccunit.test("the program draws it on the monitor with the steel palette", function()
  local r = ccunit.run("plaque.lua", { seconds = 1.5 })
  ccunit.contains(ccunit.screen("front"), "USE STAIRS")
  local mon = peripheral.wrap("front")
  local r1, g1, b1 = mon.getPaletteColour(colors.lightGray)
  ccunit.near(r1, 0xB4 / 255, 0.01)
end, { timeout = 10 })

ccunit.test("the 1x1 cab monitor gets a short plate that fits", function()
  local c = plaque.render(15, 10, { car = "A" })
  local l = lines(c)
  for _, s in ipairs({ "MOONLIFT", "ELEVATOR CO.", "C A R   A", "21 PERSONS", "ML11-A-00417", "1600kg 2.5m/s", "FIRE: STAIRS" }) do
    ccunit.contains(l, s)
  end
  -- nothing written over the border
  for y = 1, 10 do ccunit.eq(l[y]:sub(1, 1), " "); ccunit.eq(l[y]:sub(15, 15), " ") end
  ccunit.eq(l[1], (" "):rep(15)); ccunit.eq(l[10], (" "):rep(15))
end)
