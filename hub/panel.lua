-- The hub control panel: the monitor at the top of the hoistway.
local P = {}

local MODE_COLOUR = {
  normal = colors.lime, inspection = colors.yellow, fire_recall = colors.red, fire_hold = colors.red,
  firefighter = colors.orange, lockdown_trapped = colors.purple, out_of_order = colors.lightGray,
  emergency = colors.red,
}

local function put(m, x, y, text, fg, bg)
  if y < 1 then return end
  local w = m.getSize()
  if x > w then return end
  text = tostring(text)
  if x + #text - 1 > w then text = text:sub(1, w - x + 1) end
  m.setCursorPos(x, y)
  if fg then m.setTextColor(fg) end
  if bg then m.setBackgroundColor(bg) end
  m.write(text)
end

local function arrow(dir) if dir == "up" then return "\24" elseif dir == "down" then return "\25" end return " " end

local function list(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = v end
  return #s > 0 and table.concat(s, " ") or "-"
end

-- One car's block of lines: returns them as { text, colour } pairs.
local function carLines(ctl, name)
  local c, st = ctl.cars[name], ctl:carState(name)
  local calls = {}
  for i = 1, ctl.n do if c.calls[i] then calls[#calls + 1] = ctl.floors[i] end end
  local L = {}
  L[#L + 1] = { "CAR " .. name .. "  " .. (st.mode or "?"):upper(), MODE_COLOUR[st.mode] or colors.white }
  L[#L + 1] = { string.format("Floor %-3s %s %s", st.floor or "--", arrow(st.dir), st.dir or ""), colors.white }
  L[#L + 1] = { "Doors " .. st.doors .. (c.alarmOn and "  ALARM" or ""), c.alarmOn and colors.red or colors.white }
  L[#L + 1] = { "Next  " .. (st.next or "-") .. "  Stops " .. list(calls), colors.white }
  L[#L + 1] = { c.y and string.format("y %.2f  %d rpm %s", c.y, c.rpm or 0, c.release and "brake off" or "braked")
    or "y --  (no position)", colors.lightGray }
  if c.latched or c.fault then L[#L + 1] = { "! " .. (c.latched or c.fault), colors.red } end
  return L
end

-- Draws the control panel. Returns the touch targets: { { x1, x2, y, event } }.
function P.drawPanel(m, ctl, extra)
  extra = extra or {}
  local w, h = m.getSize()
  m.setBackgroundColor(colors.black)
  m.clear()
  put(m, 1, 1, string.rep(" ", w), colors.black, colors.blue)
  put(m, 2, 1, "MOONLIFT HUB", colors.white, colors.blue)
  local fire
  if ctl.fireAlarm then fire = "FIRE ALARM"
  elseif ctl.fireLatched then fire = "FIRE: turn reset key" end
  local right = (fire or "") .. (ctl.lockdown and "  LOCKDOWN" or "")
  if #right > 0 then put(m, math.max(14, w - #right), 1, right, colors.yellow, colors.blue) end
  m.setBackgroundColor(colors.black)

  local cols = (w >= 44) and 2 or 1
  local colW = math.floor(w / cols)
  local y0, maxY = 3, 3
  for k, name in ipairs(ctl.order) do
    local x = cols == 2 and ((k - 1) * colW + 2) or 2
    local y = cols == 2 and y0 or maxY
    for _, line in ipairs(carLines(ctl, name)) do
      put(m, x, y, line[1]:sub(1, colW - 2), line[2], colors.black)
      y = y + 1
    end
    if cols == 2 then maxY = math.max(maxY, y) else maxY = y + 1 end
  end
  local y = maxY + 1
  local up, down = ctl:hallCalls()
  local function fmt(l)
    local s = {}
    for _, e in ipairs(l) do s[#s + 1] = e.floor .. (e.car and ("(" .. e.car .. ")") or "") end
    return #s > 0 and table.concat(s, " ") or "-"
  end
  put(m, 2, y, "Hall up   " .. fmt(up), colors.white, colors.black); y = y + 1
  put(m, 2, y, "Hall down " .. fmt(down), colors.white, colors.black); y = y + 1
  local fireText = ctl.fireAlarm and "ALARM ON - Phase I recall" or
    (ctl.fireLatched and "alarm clear, locked out until reset at G" or "normal")
  put(m, 2, y, "Fire      " .. fireText, ctl.fireLatched and colors.red or colors.lightGray, colors.black); y = y + 1
  put(m, 2, y, "Lockdown  " .. (ctl.lockdown and "ON - L1/L2 sealed" or "off"),
    ctl.lockdown and colors.purple or colors.lightGray, colors.black); y = y + 1
  local maint = {}
  for _, n in ipairs(ctl.order) do if ctl.cars[n].mode == "inspection" then maint[#maint + 1] = n end end
  put(m, 2, y, "Maint     " .. (#maint > 0 and ("inspection: car " .. table.concat(maint, ", ")) or "none"),
    #maint > 0 and colors.yellow or colors.lightGray, colors.black); y = y + 1
  if extra.problems and #extra.problems > 0 then
    local devs, seen = {}, {}
    for _, k in ipairs(extra.problems) do
      local d = k:match("^(.-):") or k
      if not seen[d] then seen[d] = true; devs[#devs + 1] = d end
    end
    put(m, 2, y, #extra.problems .. " signal(s) not wired; missing: " .. table.concat(devs, " "), colors.orange, colors.black)
    y = y + 1
  end
  -- reset buttons for latched cars
  local targets = {}
  local bx, by = 2, math.max(y + 1, h)
  if by > h then by = h end
  for _, n in ipairs(ctl.order) do
    if ctl.cars[n].latched then
      local label = " RESET " .. n .. " "
      put(m, bx, by, label, colors.white, colors.red)
      targets[#targets + 1] = { bx, bx + #label - 1, by, { type = "reset", car = n } }
      bx = bx + #label + 2
    end
  end
  m.setBackgroundColor(colors.black)
  return targets
end

return P
