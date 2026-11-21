-- Landing computer: the hall position indicator (2x1 monitor above the door) and the hall call station (1x2 monitor
-- beside it) of one floor. Ender modem on top, optional speaker. Protocol: ../PROTOCOL.md (rednet "mmlift").
--
--   landing                      run it (startup.lua does this at boot)
--   local landing = require "landing"   in a test: returns the module without running it
--
-- Settings: mmlift.floor (or /floor.txt) is this landing's floor name. The monitors are told apart by size, the
-- wide one is the indicator and the tall one the call station; mmlift.indicator / mmlift.callpanel force a name.
-- mmlift.hub is an optional hub id, mmlift.silence the seconds without a landing message before Out of Order (5).
--
-- Hub -> landing: {type="landing", floor, car, carFloor, dir, doors, lantern, up, down, mode, outOfOrder}
-- Landing -> hub: {type="hall", floor, dir}, {type="hello", role="landing", floor}

local PROTO = "mmlift"
local M = {}

M.config = {
  floor = nil, hub = nil, silence = 5, flash = 0.25,
  floors = { "L1", "L2", "P3", "P2", "P1", "G", "2", "3", "4", "5", "6" },
  indicator = nil, callpanel = nil,
}

function M.send(msg)
  local hub = M.config.hub
  pcall(function()
    if hub then rednet.send(hub, msg, PROTO) else rednet.broadcast(msg, PROTO) end
  end)
end

local S
function M.reset()
  S = { msg = nil, last = nil, boot = os.clock(), silent = false, flash = nil }
  M.S = S
end
M.reset()

local DEAD_MODES = { fire_recall = true, fire_hold = true, firefighter = true, inspection = true,
                     emergency = true, out_of_order = true }

local function loadConfig()
  local c = M.config
  settings.load()
  c.floor = c.floor or settings.get("mmlift.floor")
  if not c.floor and fs.exists("/floor.txt") then
    local f = fs.open("/floor.txt", "r"); local l = f.readLine(); f.close()
    c.floor = l and l:match("%S+")
  end
  c.floor = tostring(c.floor or "G")
  c.hub = c.hub or settings.get("mmlift.hub")
  c.silence = settings.get("mmlift.silence") or c.silence
  c.indicator = c.indicator or settings.get("mmlift.indicator")
  c.callpanel = c.callpanel or settings.get("mmlift.callpanel")
end

-- which calls this floor has: no Up on the top floor, no Down on the bottom one
function M.buttons()
  local f = M.config.floors
  local b = {}
  if M.config.floor ~= f[#f] then b[#b + 1] = "up" end
  if M.config.floor ~= f[1] then b[#b + 1] = "down" end
  return b
end

function M.view()
  local m = S.msg or {}
  local v = { carFloor = m.carFloor, dir = m.dir, doors = m.doors, lantern = m.lantern, car = m.car,
              up = m.up, down = m.down, mode = m.mode or "normal" }
  if S.silent or not S.msg or m.outOfOrder then v.mode = "out_of_order" end
  v.dead = DEAD_MODES[v.mode] or false
  return v
end

local function canvas(w, h, bg)
  local c = { w = w, h = h }
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = { " ", colors.white, bg } end
    c[y] = row
  end
  return c
end

local function put(c, x, y, ch, fg, bg)
  local cell = c[y] and c[y][x]
  if cell then cell[1] = ch; cell[2] = fg or cell[2]; cell[3] = bg or cell[3] end
end

local function fill(c, x1, y1, x2, y2, bg)
  for y = y1, y2 do for x = x1, x2 do put(c, x, y, " ", nil, bg) end end
end

local function text(c, x, y, s, fg, bg)
  for i = 1, #s do put(c, x + i - 1, y, s:sub(i, i), fg, bg) end
end

local function center(c, y, s, fg, bg, x1, x2)
  x1, x2 = x1 or 1, x2 or c.w
  s = s:sub(1, x2 - x1 + 1)
  text(c, x1 + math.floor((x2 - x1 + 1 - #s) / 2), y, s, fg, bg)
end

local function sprite(c, x0, y0, rows, col)
  for dy, row in ipairs(rows) do
    for dx = 1, #row do
      if row:sub(dx, dx) == "X" then put(c, x0 + dx - 1, y0 + dy - 1, " ", nil, col) end
    end
  end
end

local function blit(win, c)
  win.setVisible(false)
  for y = 1, c.h do
    local t, f, b = {}, {}, {}
    for x = 1, c.w do t[x] = c[y][x][1]; f[x] = colors.toBlit(c[y][x][2]); b[x] = colors.toBlit(c[y][x][3]) end
    win.setCursorPos(1, y)
    win.blit(table.concat(t), table.concat(f), table.concat(b))
  end
  win.setVisible(true)
end

local FONT = {
  ["0"] = { "XXXXX", "X...X", "X...X", "X...X", "XXXXX" },
  ["1"] = { "..X..", ".XX..", "..X..", "..X..", ".XXX." },
  ["2"] = { "XXXXX", "....X", "XXXXX", "X....", "XXXXX" },
  ["3"] = { "XXXXX", "....X", ".XXXX", "....X", "XXXXX" },
  ["4"] = { "X...X", "X...X", "XXXXX", "....X", "....X" },
  ["5"] = { "XXXXX", "X....", "XXXXX", "....X", "XXXXX" },
  ["6"] = { "XXXXX", "X....", "XXXXX", "X...X", "XXXXX" },
  ["7"] = { "XXXXX", "....X", "...X.", "..X..", "..X.." },
  ["8"] = { "XXXXX", "X...X", "XXXXX", "X...X", "XXXXX" },
  ["9"] = { "XXXXX", "X...X", "XXXXX", "....X", "XXXXX" },
  L = { "X....", "X....", "X....", "X....", "XXXXX" },
  P = { "XXXXX", "X...X", "XXXXX", "X....", "X...." },
  G = { "XXXXX", "X....", "X..XX", "X...X", "XXXXX" },
  ["-"] = { ".....", ".....", "XXXXX", ".....", "....." },
  ["?"] = { "XXXXX", "....X", "..XXX", ".....", "..X.." },
}
local ARROW_UP = { "...X...", "..XXX..", ".XXXXX.", "...X...", "...X..." }
local ARROW_DOWN = { "...X...", "...X...", ".XXXXX.", "..XXX..", "...X..." }
-- bigger, for the arrival lantern (9 wide, 7 tall)
local LANTERN_UP = { "....X....", "...XXX...", "..XXXXX..", ".XXXXXXX.", "...XXX...", "...XXX...", "...XXX..." }
local LANTERN_DOWN = { "...XXX...", "...XXX...", "...XXX...", ".XXXXXXX.", "..XXXXX..", "...XXX...", "....X...." }

-- mode -> banner text (nil = the car letter), banner bg, banner fg
local BANNER = {
  normal = { nil, colors.gray, colors.white },
  inspection = { "MAINTENANCE", colors.orange, colors.black },
  fire_recall = { "FIRE SERVICE", colors.red, colors.white },
  fire_hold = { "FIRE SERVICE", colors.red, colors.white },
  firefighter = { "FIRE SERVICE", colors.red, colors.white },
  lockdown_trapped = { nil, colors.gray, colors.white },
  emergency = { "OUT OF ORDER", colors.gray, colors.red },
  out_of_order = { "OUT OF ORDER", colors.gray, colors.red },
}
local ACCENT = { inspection = colors.orange, fire_recall = colors.red, fire_hold = colors.red, firefighter = colors.red }

-- the indicator over the door (2x1 monitor, 36x10 at scale 0.5)
function M.renderIndicator(w, h)
  local v = M.view()
  local b = BANNER[v.mode] or BANNER.normal
  local c = canvas(w, h, colors.black)
  local ooo = v.mode == "out_of_order" or v.mode == "emergency"
  fill(c, 1, 1, w, 1, b[2])
  local title = b[1]
  if not title then
    title = v.car and ("CAR " .. v.car) or "MOONLIFT"
    if v.lantern then title = title .. "  ARRIVING" end
  end
  center(c, 1, title, b[3], b[2])

  local floor = ooo and "--" or tostring(v.carFloor or "--")
  local col = ooo and colors.gray or ACCENT[v.mode] or colors.white
  local top = 2 + math.floor((h - 3 - 5) / 2)
  local lantern = (v.lantern == "up" or v.lantern == "down") and not ooo and not v.dead
  local x2 = w - 10
  local x = 2 + math.floor((x2 - 1 - (#floor * 6 - 1)) / 2)
  for i = 1, #floor do
    sprite(c, x, top, FONT[floor:sub(i, i):upper()] or FONT["?"], col)
    x = x + 6
  end
  if lantern then
    -- the lit lantern: an amber lamp with a dark arrow cut out of it
    fill(c, w - 10, 2, w - 1, h - 1, colors.orange)
    fill(c, w - 10, 2, w - 1, 2, colors.yellow)
    sprite(c, w - 9, 3, v.lantern == "up" and LANTERN_UP or LANTERN_DOWN, colors.black)
  elseif not ooo and (v.dir == "up" or v.dir == "down") then
    sprite(c, w - 7, top, v.dir == "up" and ARROW_UP or ARROW_DOWN, ACCENT[v.mode] or colors.lime)
  end
  local msg = ooo and "Out of Order" or (v.mode == "inspection" and "Maintenance")
    or (ACCENT[v.mode] == colors.red and "Use stairs") or nil
  if msg and not lantern then center(c, h - 1, msg, ooo and colors.red or ACCENT[v.mode], colors.black, 1, w - 11) end
  fill(c, 1, h, w, h, colors.gray)
  text(c, 2, h, "FLOOR " .. M.config.floor, colors.white, colors.gray)
  local d = ({ open = "DOORS OPEN", opening = "DOORS OPENING", closing = "DOORS CLOSING" })[v.doors]
  if d and not ooo then text(c, w - #d, h, d, v.doors == "closing" and colors.yellow or colors.lime, colors.gray) end
  return c
end

local ARROW_BTN_UP = { "..X..", ".XXX.", "XXXXX" }
local ARROW_BTN_DOWN = { "XXXXX", ".XXX.", "..X.." }

-- the call station (1x2 monitor, 15x24 at scale 0.5)
function M.stationLayout(w, h)
  local kinds = M.buttons()
  local bw, bh = math.min(11, w - 4), 7
  local x1 = 1 + math.floor((w - bw) / 2)
  local list = {}
  if #kinds == 2 then
    list[1] = { id = "up", x1 = x1, x2 = x1 + bw - 1, y1 = 5, y2 = 5 + bh - 1 }
    list[2] = { id = "down", x1 = x1, x2 = x1 + bw - 1, y1 = 14, y2 = 14 + bh - 1 }
  else
    local y1 = 3 + math.floor((h - 8 - bh) / 2)
    list[1] = { id = kinds[1], x1 = x1, x2 = x1 + bw - 1, y1 = y1, y2 = y1 + bh - 1 }
  end
  return list
end

function M.renderStation(w, h)
  local v = M.view()
  local c = canvas(w, h, colors.black)
  local fire = v.mode == "fire_recall" or v.mode == "fire_hold" or v.mode == "firefighter"
  local bt = BANNER[v.mode] or BANNER.normal
  local title, bbg, bfg = bt[1] or ("FLOOR " .. M.config.floor), bt[2], bt[3]
  if v.mode == "emergency" or v.mode == "out_of_order" then title, bbg, bfg = "OUT OF ORDER", colors.red, colors.white end
  fill(c, 1, 1, w, 1, bbg)
  center(c, 1, title, bfg, bbg)
  local sub = (v.mode == "normal" or v.mode == "lockdown_trapped") and "Call elevator"
    or fire and "Use stairs" or v.mode == "inspection" and "Maintenance" or "No service"
  center(c, 2, sub, colors.lightGray, colors.black)
  for _, bn in ipairs(M.stationLayout(w, h)) do
    local lit = v[bn.id] and not v.dead
    local flashing = S.flash and S.flash.id == bn.id and os.clock() < S.flash.untilT
    local top, mid, bot, ar
    if v.dead then top, mid, bot, ar = colors.gray, colors.gray, colors.black, colors.lightGray
    elseif lit or flashing then top, mid, bot, ar = colors.yellow, colors.orange, colors.brown, colors.black
    else top, mid, bot, ar = colors.white, colors.lightGray, colors.gray, colors.black end
    fill(c, bn.x1, bn.y1, bn.x2, bn.y2, mid)
    fill(c, bn.x1, bn.y1, bn.x2, bn.y1, top)
    fill(c, bn.x1, bn.y2, bn.x2, bn.y2, bot)
    local sx = bn.x1 + math.floor((bn.x2 - bn.x1 + 1 - 5) / 2)
    sprite(c, sx, bn.y1 + 2, bn.id == "up" and ARROW_BTN_UP or ARROW_BTN_DOWN, ar)
    center(c, bn.y2 + 1, bn.id == "up" and "UP" or "DOWN", v.dead and colors.gray or colors.lightGray, colors.black,
      bn.x1, bn.x2)
  end
  return c
end

local function wrapMonitors()
  M.ind, M.sta = nil, nil
  local indName, staName = M.config.indicator, M.config.callpanel
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      local mon = peripheral.wrap(name)
      mon.setTextScale(1)
      local w, h = mon.getSize()
      local kind = (name == indName) and "ind" or (name == staName) and "sta" or (w > h and "ind" or "sta")
      if (kind == "ind" and not M.ind) or (kind == "sta" and not M.sta) then
        mon.setTextScale(0.5)
        local w2, h2 = mon.getSize()
        local rec = { name = name, win = window.create(mon, 1, 1, w2, h2, true), w = w2, h = h2 }
        if kind == "ind" then M.ind = rec else M.sta = rec end
      end
    end
  end
end

function M.draw()
  if M.ind then
    local c = M.renderIndicator(M.ind.w, M.ind.h); M.indFrame = c; blit(M.ind.win, c)
  end
  if M.sta then
    local c = M.renderStation(M.sta.w, M.sta.h); M.staFrame = c; blit(M.sta.win, c)
  end
end

local function redraw() os.queueEvent("landing_redraw") end

local function chime()
  local sp = peripheral.find("speaker")
  if sp then pcall(sp.playNote, "chime", 1, 14) end
end

function M.handle(msg)
  if type(msg) ~= "table" or msg.type ~= "landing" or tostring(msg.floor) ~= M.config.floor then return end
  local had = S.msg and S.msg.lantern
  S.msg = msg
  S.last = os.clock()
  S.silent = false
  if msg.lantern and not had then chime() end
  redraw()
end

-- A touch on the call station. Returns the message it sent, if any.
function M.touch(x, y)
  if not M.sta or M.view().dead then return nil end
  for _, bn in ipairs(M.stationLayout(M.sta.w, M.sta.h)) do
    if x >= bn.x1 and x <= bn.x2 and y >= bn.y1 and y <= bn.y2 + 1 then
      local msg = { type = "hall", floor = M.config.floor, dir = bn.id }
      M.send(msg)
      S.flash = { id = bn.id, untilT = os.clock() + M.config.flash }
      redraw()
      os.startTimer(M.config.flash + 0.05)
      return msg
    end
  end
end

local function netLoop()
  while true do
    local _, _, msg, proto = os.pullEvent("rednet_message")
    if proto == PROTO then M.handle(msg) end
  end
end

local function touchLoop()
  while true do
    local _, side, x, y = os.pullEvent("monitor_touch")
    if M.sta and side == M.sta.name then M.touch(x, y) end
  end
end

local function helloLoop()
  while not S.last do
    M.send({ type = "hello", role = "landing", floor = M.config.floor })
    sleep(3)
  end
  while true do os.pullEvent("landing_never") end
end

local function watchdog()
  while true do
    sleep(0.2)
    if not S.silent and os.clock() - (S.last or S.boot) > M.config.silence then
      S.silent = true
      redraw()
    end
  end
end

local function displayLoop()
  M.draw()
  while true do
    os.pullEvent()
    M.draw()
  end
end

function M.run()
  M.reset()
  loadConfig()
  pcall(function() peripheral.find("modem", function(n) if not rednet.isOpen(n) then rednet.open(n) end return true end) end)
  wrapMonitors()
  M.send({ type = "hello", role = "landing", floor = M.config.floor })
  parallel.waitForAny(netLoop, touchLoop, helloLoop, watchdog, displayLoop)
end

if select("#", ...) > 0 and (...) == "landing" then return M end
M.run()
