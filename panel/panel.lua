-- Cab button panel: a tall touch monitor (1 wide x 2 tall advanced monitor, text scale 0.5 = 15x24 cells) on the
-- cab's side wall, on its own small computer. Protocol: ../PROTOCOL.md (rednet "mmlift").
--
--   panel                      run it (startup.lua does this at boot)
--   local panel = require "panel"   in a test: returns the module without running it
--
-- Sends: call {floor}, door {cmd="open"|"close"|"hold"}, alarm_button, firefighter {on}, keycard (rising edge of the
-- reader's redstone input), hello {role="panel"}. Listens for the hub's panel {lit, keycard_window, mode, firefighter,
-- fireKeyAllowed, hold}. Without a panel message for `silence` seconds it shows Out of Order and sends nothing.
--
-- Settings: mmlift.car (or /car.txt), mmlift.hub (optional hub id), mmlift.keycardSide (default "back"),
-- mmlift.silence (default 5).

local PROTO = "mmlift"
local M = {}

M.config = {
  car = nil, hub = nil, keycardSide = "back", silence = 5, scale = 0.5,
  floors = { "L1", "L2", "P3", "P2", "P1", "G", "2", "3", "4", "5", "6" }, -- bottom to top
  flash = 0.25,
  press = 1,       -- a floor press shows lit this long, then follows the hub
}

function M.send(msg)
  local hub = M.config.hub
  pcall(function()
    if hub then rednet.send(hub, msg, PROTO) else rednet.broadcast(msg, PROTO) end
  end)
end

-- The reader's redstone input. Tests replace it.
function M.cardInput() return redstone.getInput(M.config.keycardSide) end

local S
function M.reset()
  S = { lit = {}, window = false, mode = "normal", lastPanel = nil, boot = os.clock(),
        silent = false, flash = nil, card = false, pressed = {}, hold = false }
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
  c.keycardSide = settings.get("mmlift.keycardSide") or c.keycardSide
  c.silence = settings.get("mmlift.silence") or c.silence
end

------------------------------------------------------------------------ drawing

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

local BANNER = {
  normal = { "CAR %s", colors.gray, colors.white },
  inspection = { "INSPECTION", colors.orange, colors.black },
  fire_recall = { "FIRE RECALL", colors.red, colors.white },
  fire_hold = { "FIRE SERVICE", colors.red, colors.white },
  firefighter = { "FIREFIGHTER", colors.red, colors.white },
  lockdown_trapped = { "LOCKDOWN", colors.red, colors.white },
  emergency = { "EMERGENCY", colors.red, colors.white },
  out_of_order = { "OUT OF ORDER", colors.red, colors.white },
}

-- Button layout for a w x h panel (15 x 24 on a 1x2 monitor at scale 0.5), drawn like a real car panel: a black
-- label with a round steel button beside it, three to a row, floors counting up left to right from the bottom.
-- Each button: x1..x2 / y1..y2 is the touch area, lx..lx2 the label, bx..bx2 the button cap, label on row y1 + 1.
function M.layout(w, h)
  local list = {}
  local floors = M.config.floors
  local cols = 3
  local rows = math.ceil(#floors / cols)
  local cw = math.floor(w / cols)                -- 5: label 2, button 2, gap 1
  local gridTop = 4
  local function slot(id, kind, col, row)       -- row 1 = top row
    local x = 1 + (col - 1) * cw
    local y = gridTop + (row - 1) * 3
    return { id = id, kind = kind, x1 = x, x2 = x + 3, y1 = y, y2 = y + 2, lx = x, lx2 = x + 1, bx = x + 2, bx2 = x + 3 }
  end
  for i, f in ipairs(floors) do
    local r = math.ceil(i / cols)
    list[#list + 1] = slot(f, "floor", (i - 1) % cols + 1, rows - r + 1)
  end
  -- door and alarm rows under the floors: a wider label on the left, its button beside it
  local function wide(id, kind, label, right, y)
    local lw = #label
    local bx = right and (w - 2) or (1 + lw)
    local lx = right and (bx - lw) or 1
    return { id = id, kind = kind, label = label, x1 = lx, x2 = bx + 1, y1 = y, y2 = y + 2, lx = lx, lx2 = lx + lw - 1,
             bx = bx, bx2 = bx + 1 }
  end
  local dy = gridTop + rows * 3 + 1
  list[#list + 1] = wide("open", "door", "\17|\16", false, dy)
  list[#list + 1] = wide("close", "door", "\16|\17", true, dy)
  list[#list + 1] = wide("alarm", "alarm", "(!)", false, dy + 4)
  list[#list + 1] = wide("hold", "door", "HOLD", true, dy + 4)
  if M.fireVisible() then
    -- the free slot after the top floor, else at the top right
    local n = #floors
    local col = n % cols + 1
    if n % cols == 0 then col = cols end
    list[#list + 1] = slot("firefighter", "fire", col, 1)
  end
  return list
end

-- the key switch shows while the hub offers it (fire service at G, card just swiped) or while it is on
function M.fireVisible()
  return not S.silent and (S.firefighter or S.fireKey) and true or false
end

-- What a floor button looks like: "lit", "dead" (no hub) or "idle". A press lights it straight away; if the hub
-- doesn't take the call (locked floor, no card) it goes dark again when the press runs out.
function M.buttonState(f)
  if S.silent then return "dead" end
  local pressed = S.pressed[f] and os.clock() < S.pressed[f]
  return (S.lit[f] or pressed) and "lit" or "idle"
end

local LABEL = { G = "*G" }   -- the star on the main floor

-- a round cap on the label's row: two cells of teletext drawing a 4x3 disc (.XX. / XXXX / .XX.).
-- The left cell needs its bottom-right pixel set, so it is drawn inverted.
local function cap(c, bt, face, panel)
  put(c, bt.bx, bt.y1 + 1, "\145", panel, face)
  put(c, bt.bx2, bt.y1 + 1, "\157", face, panel)
end

-- the pill runs under the cap too, like the reference panel
local function label(c, bt, s, fg, bg)
  fill(c, bt.lx, bt.y1 + 1, bt.bx2, bt.y1 + 1, bg)
  center(c, bt.y1 + 1, s, fg, bg, bt.lx, bt.lx2)
end

function M.render(w, h)
  local c = canvas(w, h, colors.lightGray)
  local mode = S.silent and "out_of_order" or S.mode
  local b = BANNER[mode] or BANNER.normal
  fill(c, 1, 1, w, 1, b[2])
  center(c, 1, b[1]:format(M.config.car), b[3], b[2])
  local sub, subfg = "", colors.lightGray
  if S.silent then sub, subfg = "no hub", colors.lightGray
  elseif S.window then sub, subfg = "CARD OK", colors.lime
  elseif mode == "normal" then sub = "Select floor"
  elseif mode == "inspection" then sub = "Maintenance"
  elseif mode ~= "emergency" then sub = "Use stairs" else sub = "Stay calm" end
  fill(c, 1, 2, w, 2, colors.black)
  center(c, 2, sub, subfg, colors.black)

  local dim = S.silent
  for _, bt in ipairs(M.layout(w, h)) do
    local flashing = S.flash and S.flash.id == bt.id and os.clock() < S.flash.untilT
    local face = dim and colors.gray or colors.white
    local tx = dim and colors.gray or colors.white
    if bt.kind == "floor" then
      if M.buttonState(bt.id) == "lit" then face = colors.yellow end
      label(c, bt, LABEL[bt.id] or bt.id, tx, colors.black)
      if LABEL[bt.id] and not dim then put(c, bt.lx, bt.y1 + 1, "*", colors.yellow, colors.black) end
    elseif bt.kind == "fire" then
      -- the firefighter key switch: a red label, the cap amber while the service is on
      face = S.firefighter and colors.yellow or colors.white
      label(c, bt, "FS", colors.white, colors.red)
    else
      local fg = tx
      if bt.kind == "alarm" and not dim then fg = colors.yellow end
      if bt.id == "hold" and S.hold and not dim then face = colors.yellow end
      label(c, bt, bt.label, fg, colors.black)
    end
    if flashing then face = colors.yellow end
    cap(c, bt, face, bt.kind == "fire" and colors.red or colors.black)
  end
  return c
end

function M.initDisplay()
  M.win, M.mon, M.monName, M.size = nil, nil, nil, nil
  local mon = peripheral.find("monitor")
  if not mon then return end
  mon.setTextScale(M.config.scale)
  local w, h = mon.getSize()
  M.mon = mon
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

------------------------------------------------------------------------ the loops

local function redraw() os.queueEvent("panel_redraw") end

function M.handle(msg)
  if type(msg) ~= "table" or msg.car ~= M.config.car or msg.type ~= "panel" then return end
  S.lit = type(msg.lit) == "table" and msg.lit or {}
  S.window = msg.keycard_window and true or false
  S.mode = msg.mode or "normal"
  S.firefighter = msg.firefighter == true
  S.fireKey = msg.fireKeyAllowed == true
  S.hold = msg.hold == true
  S.lastPanel = os.clock()
  S.silent = false
  redraw()
end

-- A touch at (x, y): returns what was sent, or nil.
function M.touch(x, y)
  if not M.size then return nil end
  for _, bt in ipairs(M.layout(M.size[1], M.size[2])) do
    if x >= bt.x1 and x <= bt.x2 and y >= bt.y1 and y <= bt.y2 then
      if S.silent then return nil end
      local car = M.config.car
      local msg
      if bt.kind == "floor" then msg = { type = "call", car = car, floor = bt.id }
      elseif bt.kind == "fire" then msg = { type = "firefighter", car = car, on = not S.firefighter }
      elseif bt.kind == "door" then msg = { type = "door", car = car, cmd = bt.id }
      else msg = { type = "alarm_button", car = car } end
      M.send(msg)
      if bt.kind == "floor" then
        -- lit now; stays lit only if the hub takes the call
        S.pressed[bt.id] = os.clock() + M.config.press
        os.startTimer(M.config.press + 0.05)
      else
        S.flash = { id = bt.id, untilT = os.clock() + M.config.flash }
        os.startTimer(M.config.flash + 0.05) -- wakes the display loop to clear the flash
      end
      redraw()
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
    if not M.monName or side == M.monName then M.touch(x, y) end
  end
end

local function cardLoop()
  S.card = M.cardInput() and true or false
  while true do
    local now = M.cardInput() and true or false
    if now and not S.card then M.send({ type = "keycard", car = M.config.car }) end
    S.card = now
    sleep(0.05)
  end
end

local function helloLoop()
  while not S.lastPanel do
    M.send({ type = "hello", car = M.config.car, role = "panel" })
    sleep(3)
  end
  while true do os.pullEvent("panel_never") end
end

local function watchdog()
  while true do
    sleep(0.2)
    if not S.silent and os.clock() - (S.lastPanel or S.boot) > M.config.silence then
      S.silent = true
      redraw()
    end
  end
end

-- redraw on changes only: the keycard poll and the watchdog fire timers many times a second
local function displayLoop()
  M.draw()
  while true do
    local ev = os.pullEvent()
    if ev == "timer" and (S.flash or next(S.pressed)) then
      local now = os.clock()
      if S.flash and now >= S.flash.untilT then S.flash = nil end
      for f, t in pairs(S.pressed) do if now >= t then S.pressed[f] = nil end end
      M.draw()
    elseif ev == "peripheral" or ev == "peripheral_detach" or ev == "monitor_resize" then
      -- a monitor put back (or turned round) starts at text scale 1: set it up again, or only a corner shows
      if ev ~= "monitor_resize" or not M.mon or M.mon.getTextScale() ~= M.config.scale then M.initDisplay() end
      M.draw()
    elseif ev == "panel_redraw" then
      M.draw()
    end
  end
end

function M.run()
  M.reset()
  loadConfig()
  pcall(function() peripheral.find("modem", function(n) if not rednet.isOpen(n) then rednet.open(n) end return true end) end)
  M.initDisplay()
  M.send({ type = "hello", car = M.config.car, role = "panel" })
  parallel.waitForAny(netLoop, touchLoop, cardLoop, helloLoop, watchdog, displayLoop)
end

if select("#", ...) > 0 and (...) == "panel" then return M end
M.run()
