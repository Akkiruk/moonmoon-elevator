-- Cab plaque: a static brushed-metal plate on a small monitor above the cab's button panel (own tiny computer).
-- Made for a 2x2 advanced monitor at text scale 0.5 (36x24); a smaller one drops the inspection lines.
--
--   plaque                      draw it (startup.lua does this at boot)
--   local plaque = require "plaque"   in a test: returns the module without drawing
--
-- Settings: mmlift.car (or /car.txt) gives the letter. mmlift.plaque may be a table that overrides any field of
-- plaque.defaults (maker, model, load_kg, persons, speed, serial, inspected, next_due), e.g.
--   set mmlift.plaque {serial="ML11-B-00418"}
local M = {}

M.defaults = {
  maker = "MOONLIFT ELEVATOR CO.",
  model = "ML-11 TRACTION",
  load_kg = 1600,
  persons = 21,
  speed = "2.5 m/s",
  serial = nil,            -- default: "ML11-<car>-00417"
  inspected = "2026-11-20",
  next_due = "2027-05-20",
  fire = { "IN CASE OF FIRE", "USE STAIRS" },
}

-- Steel tones, set on the monitor's palette (the 16 colours are all the plate uses).
local PALETTE = {
  [colors.lightGray] = 0xB4B8BD, -- plate
  [colors.gray] = 0x9EA3A9,      -- darker brushed streak
  [colors.white] = 0xC8CCD1,     -- lighter streak
  [colors.yellow] = 0xEEF0F2,    -- bevel highlight
  [colors.brown] = 0x5E6269,     -- bevel shadow, grooves
  [colors.black] = 0x22252B,     -- engraving
  [colors.red] = 0x9A1C1C,       -- red engraving
}
local STREAKS = { colors.lightGray, colors.gray, colors.white, colors.lightGray, colors.lightGray }

local function getCar()
  settings.load()
  local car = settings.get("mmlift.car")
  if not car and fs.exists("/car.txt") then
    local f = fs.open("/car.txt", "r"); local l = f.readLine(); f.close()
    car = l and l:match("%S+")
  end
  return tostring(car or "A")
end

local function spaced(s)
  return (s:gsub(".", "%0 "):gsub(" $", ""))
end

-- Returns a canvas { w, h, [y] = { [x] = { char, fg, bg } } }.
function M.render(w, h, opts)
  opts = opts or {}
  local d = {}
  for k, v in pairs(M.defaults) do d[k] = v end
  for k, v in pairs(opts.overrides or {}) do d[k] = v end
  local car = opts.car or "A"
  d.serial = d.serial or ("ML11-" .. car .. "-00417")

  -- brushed steel: horizontal runs of slightly different tones, from a fixed pseudo-random sequence
  local seed = 12345
  local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return 1 + math.floor(seed / 65536) % n end
  local c = { w = w, h = h }
  for y = 1, h do
    local row, x = {}, 1
    while x <= w do
      local col, run = STREAKS[rnd(#STREAKS)], 2 + rnd(9)
      for i = 0, run - 1 do if x + i <= w then row[x + i] = { " ", colors.black, col } end end
      x = x + run
    end
    c[y] = row
  end
  local function put(x, y, ch, fg, bg)
    local cell = c[y] and c[y][x]
    if cell then cell[1] = ch; cell[2] = fg or cell[2]; cell[3] = bg or cell[3] end
  end
  local function text(x, y, s, fg)
    for i = 1, #s do put(x + i - 1, y, s:sub(i, i), fg) end
  end
  local function center(y, s, fg) text(1 + math.floor((w - #s) / 2), y, s, fg) end
  local function groove(y)
    for x = 3, w - 2 do put(x, y, " ", nil, colors.brown) end
  end

  -- bevelled edge: light top and left, dark bottom and right
  for x = 1, w do put(x, 1, " ", nil, colors.yellow); put(x, h, " ", nil, colors.brown) end
  for y = 1, h do put(1, y, " ", nil, colors.yellow); put(w, y, " ", nil, colors.brown) end
  put(w, 1, " ", nil, colors.gray); put(1, h, " ", nil, colors.gray)
  for _, p in ipairs({ { 3, 3 }, { w - 2, 3 }, { 3, h - 2 }, { w - 2, h - 2 } }) do
    put(p[1], p[2], "o", colors.brown) -- rivets
  end

  local sections = {}
  sections[#sections + 1] = { { d.maker:sub(1, 8) and spaced("MOONLIFT"), colors.black },
                              { "ELEVATOR CO.", colors.black } }
  if d.maker ~= "MOONLIFT ELEVATOR CO." then sections[1] = { { d.maker, colors.black } } end
  sections[#sections + 1] = { { "MODEL " .. d.model, colors.black }, { spaced("CAR " .. car), colors.black } }
  local data = {
    { "RATED LOAD", d.load_kg .. " kg / " .. d.persons .. " pers." },
    { "RATED SPEED", d.speed },
    { "SERIAL NO.", d.serial },
  }
  if h >= 16 then
    data[#data + 1] = { "INSPECTED", d.inspected }
    data[#data + 1] = { "NEXT DUE", d.next_due }
  end
  sections[#sections + 1] = { kind = "data", rows = data }
  sections[#sections + 1] = { { d.fire[1], colors.red }, { d.fire[2], colors.red } }

  local rowsNeeded = 0
  for _, s in ipairs(sections) do rowsNeeded = rowsNeeded + (s.rows and #s.rows or #s) end
  rowsNeeded = rowsNeeded + (#sections - 1) -- one groove between sections
  local spare = (h - 4) - rowsNeeded        -- inside the border, with a 1-row margin
  local gaps = #sections + 1                -- before, between, after
  local each = math.max(0, math.floor(spare / gaps))
  local y = 2 + math.max(0, spare - each * gaps) + each
  for i, s in ipairs(sections) do
    if s.rows then
      for _, r in ipairs(s.rows) do
        text(4, y, r[1], colors.brown)
        text(w - 3 - #r[2], y, r[2], colors.black)
        y = y + 1
      end
    else
      for _, line in ipairs(s) do center(y, line[1], line[2]); y = y + 1 end
    end
    if i < #sections then
      y = y + math.floor(each / 2); groove(y); y = y + 1 + (each - math.floor(each / 2))
    end
  end
  return c
end

function M.draw(mon, opts)
  mon.setTextScale(0.5)
  for col, rgb in pairs(PALETTE) do mon.setPaletteColour(col, rgb) end
  local w, h = mon.getSize()
  local c = M.render(w, h, opts)
  M.frame = c
  for y = 1, h do
    local t, f, b = {}, {}, {}
    for x = 1, w do t[x] = c[y][x][1]; f[x] = colors.toBlit(c[y][x][2]); b[x] = colors.toBlit(c[y][x][3]) end
    mon.setCursorPos(1, y)
    mon.blit(table.concat(t), table.concat(f), table.concat(b))
  end
end

function M.run()
  local mon = peripheral.find("monitor")
  if not mon then print("No monitor found for the plaque."); return end
  local overrides = settings.get("mmlift.plaque")
  local opts = { car = getCar(), overrides = type(overrides) == "table" and overrides or nil }
  M.draw(mon, opts)
  while true do -- static; only redraw if the monitor is resized or reattached
    local ev = os.pullEvent()
    if ev == "monitor_resize" or ev == "peripheral" then
      mon = peripheral.find("monitor")
      if mon then M.draw(mon, opts) end
    end
  end
end

if select("#", ...) > 0 and (...) == "plaque" then return M end
M.run()
