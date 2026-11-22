-- Cab computer for one car (CC:Tweaked 1.120.2, Minecraft 1.21.1). Protocol: ../PROTOCOL.md (rednet "mmlift").
--
--   cab                      run the cab program (startup.lua does this at boot)
--   local cab = require "cab"   in a test: returns the module without running it
--
-- Hardware: wireless modem on top, advanced monitor (2x1) below, speaker on the right, all found by type.
--
-- Settings (`set mmlift.car B` then reboot), or a first line in /car.txt:
--   mmlift.car      "A" or "B" (the car name; also read from /car.txt)
--   mmlift.hub      optional computer id of the hub; unset = broadcast
--   mmlift.track    music track folder, .dfpwm file or URL, default /tracks/sins
--   mmlift.volume   music volume 0..3, default 1
--   mmlift.doorSide side where the door-sensor computer's redstone arrives (default "left")
--   mmlift.silence  seconds without a hub state before "Out of Order", default 5
local music = require "music"

local PROTO = "mmlift"
local M = {}

M.config = {
  car = nil,
  hub = nil,
  track = "/tracks/sins",
  volume = 1,
  silence = 5,
  posPeriod = 0.1,
  gpsTimeout = 0.15, -- host replies land within a tick; a fix that hasn't resolved by now won't
  helloEvery = 3,
  chimeGap = 0.6,
  doorSide = "left",
}

-- The position source. Tests replace it. Returns the GPS height or nil.
function M.posSource()
  -- gps.locate waits out its whole timeout when a fix comes back ambiguous (about 1 in 150 on the test server), and
  -- 0.4 s of that plus the send period went past the hub's 0.5 s lost-position limit
  local _, y = gps.locate(M.config.gpsTimeout)
  return y
end

-- The way messages leave. Tests replace it to collect them.
-- Once the hub has spoken, talk to it directly: 10 broadcasts a second woke every computer in range.
function M.send(msg)
  local hub = M.config.hub or M.hubId
  pcall(function()
    if hub then rednet.send(hub, msg, PROTO) else rednet.broadcast(msg, PROTO) end
  end)
end

-- State shared by the loops. M.reset() puts it back at boot.
local S
function M.reset()
  S = {
    state = nil,         -- last hub state fields
    lastState = nil,     -- os.clock() of the last state
    boot = os.clock(),
    silent = false,
    alarm = false,
    wantMusic = false,   -- the hub asked for play and has not asked for stop
    hubDuck = false,
    chiming = false,
    alarming = false,
    musicOn = false,     -- what we told the music player
    chimeQ = {},
    sentPos = 0,
    chimesPlayed = 0,
  }
  M.S = S
end
M.reset()

local BLOCKED = { fire_recall = true, fire_hold = true, firefighter = true, lockdown_trapped = true, emergency = true }

local function loadConfig()
  local c = M.config
  settings.load()
  c.car = c.car or settings.get("mmlift.car")
  if not c.car and fs.exists("/car.txt") then
    local f = fs.open("/car.txt", "r")
    local l = f.readLine(); f.close()
    c.car = l and l:match("%S+")
  end
  c.hub = c.hub or settings.get("mmlift.hub")
  c.doorSide = settings.get("mmlift.doorSide") or c.doorSide
  c.track = settings.get("mmlift.track") or c.track
  c.volume = settings.get("mmlift.volume") or c.volume
  c.silence = settings.get("mmlift.silence") or c.silence
  c.car = tostring(c.car or "A")
end

------------------------------------------------------------------------ the display

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

-- A canvas of w x h cells; every cell is a char with a fg and a bg colour.
local function canvas(w, h, fg, bg)
  local c = { w = w, h = h }
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = { " ", fg, bg } end
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
  local x = x1 + math.floor((x2 - x1 + 1 - #s) / 2)
  text(c, math.max(x1, x), y, s:sub(1, x2 - x1 + 1), fg, bg)
end

local function sprite(c, x0, y0, rows, col)
  for dy, row in ipairs(rows) do
    for dx = 1, #row do
      if row:sub(dx, dx) == "X" then put(c, x0 + dx - 1, y0 + dy - 1, " ", nil, col) end
    end
  end
end

local function bigWidth(s) return #s * 6 - 1 end

local function bigText(c, s, x1, x2, y0, col)
  local x = x1 + math.floor((x2 - x1 + 1 - bigWidth(s)) / 2)
  for i = 1, #s do
    sprite(c, x, y0, FONT[s:sub(i, i):upper()] or FONT["?"], col)
    x = x + 6
  end
end

-- mode -> banner text, banner colours, accent colour of floor and arrow
local MODES = {
  normal = { "", colors.gray, colors.white, colors.white, colors.lime },
  inspection = { "INSPECTION SERVICE", colors.orange, colors.black, colors.orange, colors.orange },
  fire_recall = { "FIRE RECALL", colors.red, colors.white, colors.red, colors.red },
  fire_hold = { "FIRE SERVICE", colors.red, colors.white, colors.red, colors.red },
  firefighter = { "FIREFIGHTER SERVICE", colors.red, colors.white, colors.red, colors.red },
  lockdown_trapped = { "SECURITY LOCKDOWN", colors.red, colors.white, colors.red, colors.red },
  emergency = { "EMERGENCY", colors.red, colors.white, colors.red, colors.red },
  out_of_order = { "OUT OF ORDER", colors.gray, colors.white, colors.gray, colors.gray },
  boot = { "STARTING", colors.gray, colors.white, colors.gray, colors.gray },
}

local DOORS = {
  open = { "DOORS OPEN", colors.lime },
  opening = { "DOORS OPENING", colors.lime },
  closing = { "DOORS CLOSING", colors.yellow },
  closed = { "DOORS CLOSED", colors.white },
}

-- view: { floor, dir, doors, mode, message, next }. Returns a canvas.
function M.render(view, car, w, h)
  local mode = MODES[view.mode] and view.mode or "normal"
  local m = MODES[mode]
  local c = canvas(w, h, colors.white, colors.black)
  local banner = (mode == "normal") and ("MOONLIFT  CAR " .. car) or m[1]
  local bannerTxt = banner
  if mode == "normal" then bannerTxt = banner end
  fill(c, 1, 1, w, 1, m[2])
  center(c, 1, bannerTxt, m[3], m[2])
  local floor = tostring(view.floor or "--")
  if mode == "out_of_order" or mode == "boot" then floor = "--" end

  if w >= 30 and h >= 10 then
    local top = 2 + math.floor((h - 3 - 5) / 2)
    local aw = 9
    if bigWidth(floor) > w - aw - 2 then
      center(c, top + 2, floor, m[4], colors.black, 1, w - aw)
    else
      bigText(c, floor, 2, w - aw, top, m[4])
    end
    if view.dir == "up" then sprite(c, w - 7, top, ARROW_UP, m[5])
    elseif view.dir == "down" then sprite(c, w - 7, top, ARROW_DOWN, m[5]) end
  else
    -- very small monitor: plain text
    local arrow = view.dir == "up" and "\30" or view.dir == "down" and "\31" or " "
    center(c, math.ceil(h / 2), floor .. " " .. arrow, m[4], colors.black)
  end

  if view.message and view.message ~= "" and h >= 4 then
    local mc = (mode == "normal") and colors.white or (mode == "inspection") and colors.orange
      or (mode == "out_of_order" or mode == "boot") and colors.red or colors.red
    center(c, h - 1, view.message, mc, colors.black)
  end
  if h >= 3 then
    fill(c, 1, h, w, h, colors.gray)
    local d = DOORS[view.doors]
    if d and mode ~= "out_of_order" and mode ~= "boot" then text(c, 2, h, d[1], d[2], colors.gray) end
    if view.next and mode ~= "out_of_order" and mode ~= "boot" and mode ~= "lockdown_trapped" then
      local s = "NEXT " .. tostring(view.next)
      text(c, w - #s, h, s, colors.white, colors.gray)
    end
  end
  return c
end

-- What is shown now: the last state, or Out of Order when the hub has been silent.
function M.view()
  local v = {}
  if S.silent then
    v.mode = "out_of_order"; v.message = "Out of Order"
  elseif S.state then
    for k, val in pairs(S.state) do v[k] = val end
    v.mode = v.mode or "normal"
  else
    v.mode = "boot"; v.message = "Waiting for hub"
  end
  return v
end

local function blitLine(row)
  local t, f, b = {}, {}, {}
  for x = 1, #row do
    t[x] = row[x][1]; f[x] = colors.toBlit(row[x][2]); b[x] = colors.toBlit(row[x][3])
  end
  return table.concat(t), table.concat(f), table.concat(b)
end

function M.initDisplay()
  local mon = peripheral.find("monitor")
  if not mon then M.win = nil; return end
  mon.setTextScale(M.config.scale or 0.5)
  local w, h = mon.getSize()
  if w < 30 or h < 10 then mon.setTextScale(1); w, h = mon.getSize() end
  M.win = window.create(mon, 1, 1, w, h, true)
  M.size = { w, h }
end

function M.draw()
  local win = M.win
  if not win then return end
  local w, h = M.size[1], M.size[2]
  local c = M.render(M.view(), M.config.car, w, h)
  M.frame = c
  win.setVisible(false)
  for y = 1, h do
    local t, f, b = blitLine(c[y])
    win.setCursorPos(1, y)
    win.blit(t, f, b)
  end
  win.setVisible(true)
end

------------------------------------------------------------------------ audio

local function note(instrument, pitch, vol)
  local sp = peripheral.find("speaker")
  if sp then pcall(sp.playNote, instrument, vol or 3, pitch) end
end

-- Decide what the music player should be doing from the whole picture.
function M.applyMusic()
  local mode = S.state and S.state.mode
  local should = S.wantMusic and not S.silent and not (mode and BLOCKED[mode])
  if should and not S.musicOn then
    music.setVolume(M.config.volume)
    music.play(M.config.track)
  elseif not should and S.musicOn then
    music.stop()
  end
  S.musicOn = should
  music.duck(should and (S.hubDuck or S.chiming or S.alarming) or false)
end

local function wakeAudio() os.queueEvent("cab_audio") end

local function wakeDraw() os.queueEvent("cab_redraw") end

local function handle(msg)
  if type(msg) ~= "table" or msg.car ~= M.config.car then return end
  local t = msg.type
  if t == "state" then
    local st = {}
    for k, v in pairs(msg) do if k ~= "type" and k ~= "car" then st[k] = v end end
    S.state = st
    S.lastState = os.clock()
    S.silent = false
    if msg.music == "play" then S.wantMusic = true elseif msg.music == "stop" then S.wantMusic = false end
    M.applyMusic()
    wakeDraw()
  elseif t == "chime" then
    S.chimeQ[#S.chimeQ + 1] = math.max(1, math.min(3, tonumber(msg.count) or 1))
    wakeAudio()
  elseif t == "alarm" then
    S.alarm = msg.on and true or false
    wakeAudio()
  elseif t == "music" then
    local cmd = msg.cmd
    if cmd == "play" then S.wantMusic = true; S.hubDuck = false
    elseif cmd == "stop" then S.wantMusic = false; S.hubDuck = false
    elseif cmd == "duck" then S.hubDuck = true
    elseif cmd == "resume" then S.hubDuck = false end
    M.applyMusic()
  end
end
M.handle = handle

------------------------------------------------------------------------ the loops

-- rednet_message arrives as: event, sender, message, protocol
local function netLoop()
  while true do
    local _, from, msg, proto = os.pullEvent("rednet_message")
    if proto == PROTO then
      -- only the hub sends our car's state; a replaced hub computer gets picked up the same way
      if type(msg) == "table" and msg.type == "state" and msg.car == M.config.car then M.hubId = from end
      handle(msg)
    end
  end
end

local function posLoop()
  local nextAt = os.clock()
  while true do
    local ok, y = pcall(M.posSource)
    if not ok then y = nil end
    local t = os.epoch("utc")
    if y then M.send({ type = "pos", car = M.config.car, y = y, t = t })
    else M.send({ type = "pos", car = M.config.car, err = "nogps", t = t }) end
    S.sentPos = S.sentPos + 1
    nextAt = nextAt + M.config.posPeriod
    local d = nextAt - os.clock()
    if d < 0.01 then d = 0.01; nextAt = os.clock() end
    sleep(d)
  end
end

-- Hello until the hub answers. Never returns (waitForAny would stop everything if it did).
local function helloLoop()
  while not S.lastState do
    M.send({ type = "hello", car = M.config.car })
    sleep(M.config.helloEvery)
  end
  while true do os.pullEvent("cab_never") end
end

-- Silence watchdog: no state for a while means Out of Order (we keep sending positions).
local function watchdog()
  while true do
    sleep(0.2)
    local since = S.lastState or S.boot
    if not S.silent and os.clock() - since > M.config.silence then
      S.silent = true
      S.alarm = false -- a dead hub cannot turn it off
      M.applyMusic()
      wakeDraw()
    end
  end
end

local function displayLoop()
  M.draw()
  while true do
    os.pullEvent("cab_redraw")
    M.draw()
  end
end

local function chimeLoop()
  while true do
    if #S.chimeQ == 0 then
      os.pullEvent("cab_audio")
    else
      S.chiming = true
      M.applyMusic()
      sleep(0.15) -- let the music go quiet first
      while #S.chimeQ > 0 do
        local n = table.remove(S.chimeQ, 1)
        for i = 1, n do
          note("bell", 18)
          note("chime", 18)
          S.chimesPlayed = S.chimesPlayed + 1
          sleep(M.config.chimeGap)
        end
      end
      S.chiming = false
      M.applyMusic()
    end
  end
end

local function alarmLoop()
  local hi = true
  while true do
    if S.alarm then
      if not S.alarming then S.alarming = true; M.applyMusic(); sleep(0.1) end
      note("pling", hi and 20 or 8)
      hi = not hi
      sleep(0.3)
    else
      if S.alarming then S.alarming = false; M.applyMusic() end
      os.pullEvent("cab_audio")
    end
  end
end

-- Door sensor: doorsensor.lua on a small computer next to the door puts a redstone level into the side
-- mmlift.doorSide (default "left"): 15 = open, 8 = closed, anything else (0 when it is down) = fault.
-- Sends {type="door_state", car, open, ok} on change and every second.
function M.doorLevel()
  return redstone.getAnalogInput(M.config.doorSide)
end

function M.readDoor()
  local level = M.doorLevel()
  return level == 15, (level == 15 or level == 8)
end

function M.doorLoop()
  local last, lastAt
  while true do
    local open, ok = M.readDoor()
    local key = tostring(open) .. tostring(ok)
    if key ~= last or os.clock() - lastAt >= 1 then
      last, lastAt = key, os.clock()
      M.send({ type = "door_state", car = M.config.car, open = open, ok = ok })
    end
    sleep(0.1)
  end
end

-- Run every loop side by side. Nothing in here blocks for long, so no event is held up behind another.
function M.run()
  M.reset()
  loadConfig()
  pcall(function() peripheral.find("modem", function(n) if not rednet.isOpen(n) then rednet.open(n) end return true end) end)
  M.initDisplay()
  M.send({ type = "hello", car = M.config.car })
  parallel.waitForAny(netLoop, posLoop, helloLoop, watchdog, displayLoop, chimeLoop, alarmLoop, music.run, M.doorLoop)
end

if select("#", ...) > 0 and (...) == "cab" then return M end -- required by a test
M.run()
