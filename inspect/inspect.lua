-- Roof inspection station: a small computer on the cab roof with a wireless modem and a 1x1 advanced monitor lying
-- flat (read from above). Protocol: ../PROTOCOL.md (rednet "mmlift").
--
--   inspect                      run it (startup.lua does this at boot)
--   local inspect = require "inspect"   in a test: returns the module without running it
--
-- Three touch zones: INSPECT (toggle), UP and DOWN (jog, only while inspection is on). INSPECT sends
-- {type="inspect", car, on}. A jog sends {type="inspect_move", car, dir} at once and every 0.3 s; touching the same
-- arrow again, or any other zone, stops it with {dir="stop"}. The hub's "state" message gives the mode and floor.
-- No state for 5 s: "No hub", and any jog stops.
-- Settings: mmlift.car (or /car.txt), mmlift.hub (optional hub id), mmlift.silence (default 5).

local PROTO = "mmlift"
local M = {}

M.config = { car = nil, hub = nil, silence = 5, keepalive = 0.3, grace = 1.5 }

function M.send(msg)
  local hub = M.config.hub
  pcall(function()
    if hub then rednet.send(hub, msg, PROTO) else rednet.broadcast(msg, PROTO) end
  end)
end

local S
function M.reset()
  S = { on = false, pendingUntil = 0, jog = nil, nextMove = 0, mode = nil, floor = nil, last = nil,
        boot = os.clock(), silent = false }
  M.S = S
end
M.reset()

local function loadConfig()
  local c = M.config
  settings.load()
  c.car = c.car or settings.get("mmlift.car")
  if not c.car and fs.exists("/car.txt") then
    local f = fs.open("/car.txt", "r"); local l = f.readLine(); f.close()
    c.car = l and l:match("%S+")
  end
  c.car = tostring(c.car or "A")
  c.hub = c.hub or settings.get("mmlift.hub")
  c.silence = settings.get("mmlift.silence") or c.silence
end

-- zones for a w x h screen (15 x 10 on a 1x1 monitor at scale 0.5)
function M.zones(w, h)
  local half = math.floor((w - 1) / 2)
  return {
    { id = "inspect", x1 = 1, x2 = w, y1 = 3, y2 = 5 },
    { id = "up", x1 = 1, x2 = half, y1 = 7, y2 = h },
    { id = "down", x1 = w - half + 1, x2 = w, y1 = 7, y2 = h },
  }
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

local function center(c, y, s, fg, bg, x1, x2)
  x1, x2 = x1 or 1, x2 or c.w
  s = s:sub(1, x2 - x1 + 1)
  local x = x1 + math.floor((x2 - x1 + 1 - #s) / 2)
  for i = 1, #s do put(c, x + i - 1, y, s:sub(i, i), fg, bg) end
end

local function sprite(c, x0, y0, rows, col)
  for dy, row in ipairs(rows) do
    for dx = 1, #row do
      if row:sub(dx, dx) == "X" then put(c, x0 + dx - 1, y0 + dy - 1, " ", nil, col) end
    end
  end
end

local ARROW = { up = { "..X..", ".XXX.", "XXXXX" }, down = { "XXXXX", ".XXX.", "..X.." } }

local MODE_TEXT = {
  normal = "NORMAL", inspection = "INSPECTION", fire_recall = "FIRE RECALL", fire_hold = "FIRE SERVICE",
  firefighter = "FIREFIGHTER", lockdown_trapped = "LOCKDOWN", emergency = "EMERGENCY", out_of_order = "OUT OF ORDER",
}

function M.render(w, h)
  local c = canvas(w, h, colors.black)
  local bar, barfg, line1, line2
  if S.silent then
    bar, barfg, line1, line2 = colors.red, colors.white, "NO HUB", ""
  else
    local mode = S.mode or "normal"
    bar, barfg = colors.gray, colors.white
    if mode == "inspection" then bar, barfg = colors.orange, colors.black
    elseif mode ~= "normal" then bar = colors.red end
    line1 = S.mode and (MODE_TEXT[mode] or mode:upper()) or "WAITING"
    line2 = "CAR " .. M.config.car .. (S.floor and ("  FL " .. S.floor) or "")
  end
  fill(c, 1, 1, w, 1, bar)
  center(c, 1, line1, barfg, bar)
  center(c, 2, line2, colors.lightGray, colors.black)

  local zs = M.zones(w, h)
  local z = zs[1]
  local on = S.on and not S.silent
  local bg, fg = colors.gray, colors.lightGray
  if on then bg, fg = colors.orange, colors.black end
  fill(c, z.x1, z.y1, z.x2, z.y2, bg)
  center(c, z.y1 + 1, "INSPECT", fg, bg, z.x1, z.x2)
  center(c, z.y1 + 2, on and "ON" or "OFF", fg, bg, z.x1, z.x2)
  for i = 2, 3 do
    local a = zs[i]
    local abg, afg = colors.gray, colors.lightGray
    if on then abg, afg = colors.lightGray, colors.black end
    if S.jog == a.id then abg, afg = colors.lime, colors.black end
    fill(c, a.x1, a.y1, a.x2, a.y2, abg)
    local sx = a.x1 + math.floor((a.x2 - a.x1 + 1 - 5) / 2)
    sprite(c, sx, a.y1, ARROW[a.id], afg)
    center(c, a.y1 + 3, a.id == "up" and "UP" or "DOWN", afg, abg, a.x1, a.x2)
  end
  return c
end

function M.initDisplay()
  local mon = peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  M.monName = peripheral.getName(mon)
  M.win = window.create(mon, 1, 1, w, h, true)
  M.size = { w, h }
end

function M.draw()
  if not M.win then return end
  local w, h = M.size[1], M.size[2]
  local c = M.render(w, h)
  M.frame = c
  M.win.setVisible(false)
  for y = 1, h do
    local t, f, b = {}, {}, {}
    for x = 1, w do t[x] = c[y][x][1]; f[x] = colors.toBlit(c[y][x][2]); b[x] = colors.toBlit(c[y][x][3]) end
    M.win.setCursorPos(1, y)
    M.win.blit(table.concat(t), table.concat(f), table.concat(b))
  end
  M.win.setVisible(true)
end

local function redraw() os.queueEvent("inspect_redraw") end

local function stopJog()
  if S.jog then
    S.jog = nil
    M.send({ type = "inspect_move", car = M.config.car, dir = "stop" })
  end
end

function M.handle(msg)
  if type(msg) ~= "table" or msg.car ~= M.config.car or msg.type ~= "state" then return end
  S.mode, S.floor = msg.mode, msg.floor
  S.last = os.clock()
  S.silent = false
  if os.clock() >= S.pendingUntil then S.on = (msg.mode == "inspection") end
  if not S.on then stopJog() end
  redraw()
end

-- A touch at (x, y)
function M.touch(x, y)
  if not M.size then return end
  for _, z in ipairs(M.zones(M.size[1], M.size[2])) do
    if x >= z.x1 and x <= z.x2 and y >= z.y1 and y <= z.y2 then
      local car = M.config.car
      if z.id == "inspect" then
        stopJog()
        if S.silent then return end
        S.on = not S.on
        S.pendingUntil = os.clock() + M.config.grace
        M.send({ type = "inspect", car = car, on = S.on })
      elseif S.jog then
        stopJog() -- the same arrow or the other one: either way it stops
      elseif S.on and not S.silent then
        S.jog = z.id
        S.nextMove = os.clock() + M.config.keepalive
        M.send({ type = "inspect_move", car = car, dir = z.id })
      end
      redraw()
      return
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
    if not M.monName or side == M.monName then M.touch(x, y) end
  end
end

-- resend the jog while it lasts; idle (no timers) when nobody is jogging
local function moveLoop()
  while true do
    if not S.jog then
      os.pullEvent("inspect_redraw")
    else
      sleep(math.max(0.05, S.nextMove - os.clock()))
      if S.jog and os.clock() >= S.nextMove then
        S.nextMove = os.clock() + M.config.keepalive
        M.send({ type = "inspect_move", car = M.config.car, dir = S.jog })
      end
    end
  end
end

local function helloLoop()
  while not S.last do
    M.send({ type = "hello", car = M.config.car, role = "inspect" })
    sleep(3)
  end
  while true do os.pullEvent("inspect_never") end
end

local function watchdog()
  while true do
    sleep(0.2)
    if not S.silent and os.clock() - (S.last or S.boot) > M.config.silence then
      S.silent = true
      S.on = false
      stopJog()
      redraw()
    end
  end
end

local function displayLoop()
  M.draw()
  while true do
    local ev = os.pullEvent()
    if ev == "inspect_redraw" or ev == "monitor_resize" then M.draw() end
  end
end

function M.run()
  M.reset()
  loadConfig()
  pcall(function() peripheral.find("modem", function(n) if not rednet.isOpen(n) then rednet.open(n) end return true end) end)
  M.initDisplay()
  M.send({ type = "hello", car = M.config.car, role = "inspect" })
  parallel.waitForAny(netLoop, touchLoop, moveLoop, helloLoop, watchdog, displayLoop)
end

if select("#", ...) > 0 and (...) == "inspect" then return M end
M.run()
