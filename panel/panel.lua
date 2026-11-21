-- Cab button panel: a tall touch monitor (1 wide x 2 tall advanced monitor, text scale 0.5 = 15x24 cells) on the
-- cab's side wall, on its own small computer. Protocol: ../PROTOCOL.md (rednet "mmlift").
--
--   panel                      run it (startup.lua does this at boot)
--   local panel = require "panel"   in a test: returns the module without running it
--
-- Sends: call {floor}, door {cmd="open"|"close"}, alarm_button, firefighter {on}, keycard (rising edge of the reader's redstone input),
-- hello {role="panel"}. Listens for the hub's panel {lit, locked, keycard_window, mode, firefighter, fireKeyAllowed}.
-- Without a panel message for `silence` seconds it shows Out of Order and sends nothing.
--
-- Settings: mmlift.car (or /car.txt), mmlift.hub (optional hub id), mmlift.keycardSide (default "back"),
-- mmlift.silence (default 5), mmlift.keyFloors (default L1, L2: the floors that need the card).

local PROTO = "mmlift"
local M = {}

M.config = {
  car = nil, hub = nil, keycardSide = "back", silence = 5, scale = 0.5,
  floors = { "L1", "L2", "P3", "P2", "P1", "G", "2", "3", "4", "5", "6" }, -- bottom to top
  keyFloors = { L1 = true, L2 = true },
  flash = 0.25,
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
  S = { lit = {}, locked = {}, window = false, mode = "normal", lastPanel = nil, boot = os.clock(),
        silent = false, flash = nil, card = false }
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
  local kf = settings.get("mmlift.keyFloors")
  if type(kf) == "table" then c.keyFloors = {}; for _, f in ipairs(kf) do c.keyFloors[f] = true end end
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

-- Button layout for a w x h panel (15 x 24 on a 1x2 monitor at scale 0.5). Returns the list of buttons.
function M.layout(w, h)
  local list = {}
  local n = #M.config.floors
  local slots = math.ceil(n / 2)
  local bw = math.floor((w - 1) / 2)             -- 7
  local x0 = 1 + math.floor((w - (bw * 2 + 1)) / 2)
  local gridBottom = h - 4                       -- the door row takes the last 4
  for i, f in ipairs(M.config.floors) do
    local row = math.ceil(i / 2)                 -- 1 = bottom row
    local col = (i - 1) % 2
    local y2 = gridBottom - (row - 1) * 3
    local x1 = x0 + col * (bw + 1)
    list[#list + 1] = { id = f, kind = "floor", x1 = x1, x2 = x1 + bw - 1, y1 = y2 - 2, y2 = y2 }
  end
  local fy1 = h - 2
  local fw = 4
  local gap = 1
  local fx = 1 + math.floor((w - (fw * 3 + gap * 2)) / 2)
  for _, k in ipairs({ { "open", "<|>" }, { "close", ">|<" }, { "alarm", "(!)" } }) do
    list[#list + 1] = { id = k[1], kind = k[1] == "alarm" and "alarm" or "door", label = k[2],
                        x1 = fx, x2 = fx + fw - 1, y1 = fy1, y2 = fy1 + 2 }
    fx = fx + fw + gap
  end
  if M.fireVisible() then
    -- the free slot next to the top floor button
    local top
    for _, b in ipairs(list) do if b.kind == "floor" and (not top or b.y1 < top.y1) then top = b end end
    list[#list + 1] = { id = "firefighter", kind = "fire", x1 = top.x1 + bw + 1, x2 = top.x1 + 2 * bw, y1 = top.y1,
                        y2 = top.y2 }
  end
  return list
end

-- the key switch shows while the hub offers it (fire service at G, card just swiped) or while it is on
function M.fireVisible()
  return not S.silent and (S.firefighter or S.fireKey) and true or false
end

-- What a floor button looks like: "lit", "dead" or "idle"; keyed floors also show "keyed" (locked) or "open".
function M.buttonState(f)
  local dead = S.silent or S.locked[f]
  local key = M.config.keyFloors[f]
  if key and not S.window then dead = true end
  local look = dead and "dead" or (S.lit[f] and "lit" or "idle")
  return look, key and (dead and "locked" or "open") or nil
end

function M.render(w, h)
  local c = canvas(w, h, colors.black)
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
  center(c, 2, sub, subfg, colors.black)

  for _, bt in ipairs(M.layout(w, h)) do
    local flashing = S.flash and S.flash.id == bt.id and os.clock() < S.flash.untilT
    if bt.kind == "floor" then
      local look, key = M.buttonState(bt.id)
      local top, mid, bot, tx, mark
      if look == "lit" then top, mid, bot, tx = colors.yellow, colors.orange, colors.brown, colors.black
      elseif look == "dead" then top, mid, bot, tx = colors.gray, colors.gray, colors.black, colors.lightGray
      else top, mid, bot, tx = colors.white, colors.lightGray, colors.gray, colors.black end
      if flashing then top, mid, bot, tx = colors.white, colors.yellow, colors.orange, colors.black end
      fill(c, bt.x1, bt.y1, bt.x2, bt.y1, top)
      fill(c, bt.x1, bt.y1 + 1, bt.x2, bt.y1 + 1, mid)
      fill(c, bt.x1, bt.y2, bt.x2, bt.y2, bot)
      center(c, bt.y1 + 1, bt.id, tx, mid, bt.x1, bt.x2)
      if key == "locked" then
        center(c, bt.y2, "LOCKED", colors.red, bot, bt.x1, bt.x2)
        put(c, bt.x1, bt.y1 + 1, "\7", colors.red, mid)
      elseif key == "open" then
        center(c, bt.y2, "OPEN", colors.lime, bot, bt.x1, bt.x2)
        put(c, bt.x1, bt.y1 + 1, "\7", colors.green, mid)
      end
    elseif bt.kind == "fire" then
      -- a key switch: red when off, amber when the firefighter service is on
      local on = S.firefighter
      local top, mid, bot, tx = colors.red, colors.red, colors.brown, colors.white
      if on then top, mid, bot, tx = colors.yellow, colors.orange, colors.brown, colors.black end
      if flashing then top, mid, bot, tx = colors.white, colors.yellow, colors.orange, colors.black end
      fill(c, bt.x1, bt.y1, bt.x2, bt.y1, top)
      fill(c, bt.x1, bt.y1 + 1, bt.x2, bt.y1 + 1, mid)
      fill(c, bt.x1, bt.y2, bt.x2, bt.y2, bot)
      center(c, bt.y1, "FIRE", tx, top, bt.x1, bt.x2)
      center(c, bt.y1 + 1, "(o)=\16", tx, mid, bt.x1, bt.x2)  -- key head and blade
      center(c, bt.y2, on and "ON" or "KEY", tx, bot, bt.x1, bt.x2)
    else
      local bg, fgc = colors.gray, colors.white
      if bt.kind == "alarm" then bg = colors.red end
      if S.silent then bg, fgc = colors.gray, colors.lightGray end
      if flashing then bg, fgc = colors.yellow, colors.black end
      fill(c, bt.x1, bt.y1, bt.x2, bt.y2, bg)
      center(c, bt.y1 + 1, bt.label, fgc, bg, bt.x1, bt.x2)
    end
  end
  return c
end

function M.initDisplay()
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
  S.locked = type(msg.locked) == "table" and msg.locked or {}
  S.window = msg.keycard_window and true or false
  S.mode = msg.mode or "normal"
  S.firefighter = msg.firefighter == true
  S.fireKey = msg.fireKeyAllowed == true
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
      S.flash = { id = bt.id, untilT = os.clock() + M.config.flash }
      redraw()
      os.startTimer(M.config.flash + 0.05) -- wakes the display loop to clear the flash
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
    if ev == "timer" and S.flash then
      if os.clock() >= S.flash.untilT then S.flash = nil end
      M.draw()
    elseif ev == "panel_redraw" or ev == "monitor_resize" then
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
