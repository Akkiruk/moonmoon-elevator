-- Run from this folder: craftos-mcp test cab.test.lua --timeout 120
-- The position source and the way messages leave are small functions in cab.lua (cab.posSource, cab.send), so the tests
-- fake them: GPS cannot be emulated for a moving car. Hub messages arrive as real rednet_message events.
local cab = require "cab"
local realDoorLevel = cab.doorLevel
local music = require "music"

local log, sent, reader, fakeY
local realFind = peripheral.find
local realSpeaker = realFind("speaker")

local fakeSpeaker = setmetatable({
  playAudio = function(buf, vol)
    local ok = realSpeaker.playAudio(buf, vol)
    if ok then log[#log + 1] = { k = "audio", t = os.clock() } end
    return ok
  end,
  stop = function() log[#log + 1] = { k = "stop", t = os.clock() }; return realSpeaker.stop() end,
  playNote = function(inst, vol, pitch)
    log[#log + 1] = { k = "note", inst = inst, pitch = pitch, t = os.clock() }
    return realSpeaker.playNote(inst, vol, pitch)
  end,
}, { __index = realSpeaker })

peripheral.find = function(t, f)
  if t == "speaker" then return fakeSpeaker end
  if t == "block_reader" then return reader end
  return realFind(t, f)
end

local function write(path, chunks)
  local f = fs.open(path, "wb")
  for _ = 1, chunks do f.write(string.rep("\x55\xAA", 2048)) end
  f.close()
end
write("/t3.dfpwm", 3)

local function setup(silence)
  log, sent = {}, {}
  reader = nil
  fakeY = 100.25
  cab.config.car = "A"
  cab.config.track = "/t3.dfpwm"
  cab.config.silence = silence or 30
  cab.posSource = function() return fakeY end
  cab.send = function(m) m.at = os.clock(); sent[#sent + 1] = m end
end

local function with(scenario)
  parallel.waitForAny(cab.run, function() scenario() end)
  music.stop()
end

local function feed(msg, wait)
  os.queueEvent("rednet_message", 9, msg, "mmlift")
  sleep(wait or 0.15)
end

local function state(t)
  local s = { type = "state", car = "A", floor = "G", doors = "closed", mode = "normal" }
  for k, v in pairs(t or {}) do s[k] = v end
  return s
end

local function rows()
  local out = {}
  for y = 1, cab.frame.h do
    local t = {}
    for x = 1, cab.frame.w do t[x] = cab.frame[y][x][1] end
    out[y] = table.concat(t)
  end
  return out
end

local function bg(x, y) return cab.frame[y][x][3] end
local function fg(x, y) return cab.frame[y][x][2] end

-- how many cells of a row (between x1 and x2) have this background
local function countBg(y, x1, x2, col)
  local n = 0
  for x = x1, x2 do if bg(x, y) == col then n = n + 1 end end
  return n
end

local function count(kind, inst)
  local n = 0
  for _, e in ipairs(log) do if e.k == kind and (not inst or e.inst == inst) then n = n + 1 end end
  return n
end

local function ofType(t)
  local o = {}
  for _, m in ipairs(sent) do if m.type == t then o[#o + 1] = m end end
  return o
end

ccunit.test("boot: hello is sent, display waits for the hub", function()
  setup()
  with(function() sleep(0.5) end)
  ccunit.eq(ofType("hello")[1].car, "A")
  ccunit.contains(rows(), "STARTING")
  ccunit.eq(cab.size[1], 36)
  ccunit.eq(cab.size[2], 10)
end, { timeout = 10 })

ccunit.test("normal: floor, arrow up, doors and next stop", function()
  setup()
  with(function()
    feed(state({ floor = "G", dir = "up", doors = "open", next = "3" }))
    local r = rows()
    ccunit.contains(r[1], "MOONLIFT  CAR A")
    ccunit.eq(bg(5, 1), colors.gray)
    ccunit.contains(r[10], "DOORS OPEN")
    ccunit.contains(r[10], "NEXT 3")
    -- the big G is white, the up arrow lime: 3 cells wide on its second row, 1 on its fourth
    ccunit.truthy(countBg(4, 1, 26, colors.white) >= 1, "big floor drawn in white")
    ccunit.eq(countBg(4, 27, 36, colors.lime), 3)
    ccunit.eq(countBg(6, 27, 36, colors.lime), 1)
    local top = countBg(3, 1, 26, colors.white)
    ccunit.eq(top, 5, "top bar of the G")
    -- the real monitor got the same text
    ccunit.eq(cab.win.getLine(10):sub(2, 11), "DOORS OPEN")
    feed(state({ floor = "P1", dir = "down", doors = "closing" }))
    ccunit.eq(countBg(4, 27, 36, colors.lime), 1)
    ccunit.eq(countBg(6, 27, 36, colors.lime), 3)
    ccunit.contains(rows()[10], "DOORS CLOSING")
    feed(state({ floor = "2", dir = nil, doors = "closed", message = "Doors closing" }))
    ccunit.contains(rows()[9], "Doors closing")
    ccunit.eq(countBg(4, 27, 36, colors.lime), 0)
  end)
end, { timeout = 15 })

ccunit.test("fire: red banner, red floor, red message", function()
  setup()
  with(function()
    feed(state({ floor = "G", mode = "fire_recall", message = "Fire - exit at G", doors = "open" }))
    local r = rows()
    ccunit.contains(r[1], "FIRE RECALL")
    ccunit.eq(bg(3, 1), colors.red)
    ccunit.eq(fg(18, 1), colors.white)
    ccunit.truthy(countBg(3, 1, 26, colors.red) >= 3, "floor is red")
    ccunit.eq(countBg(3, 1, 26, colors.white), 0)
    ccunit.contains(r[9], "Fire - exit at G")
    ccunit.eq(fg(math.floor((36 - 16) / 2) + 2, 9), colors.red)
    for mode, banner in pairs({ firefighter = "FIREFIGHTER SERVICE", emergency = "EMERGENCY", fire_hold = "FIRE SERVICE",
      lockdown_trapped = "SECURITY LOCKDOWN" }) do
      feed(state({ mode = mode }))
      ccunit.contains(rows()[1], banner)
      ccunit.eq(bg(2, 1), colors.red)
    end
  end)
end, { timeout = 15 })

ccunit.test("inspection: amber banner and floor", function()
  setup()
  with(function()
    feed(state({ floor = "4", mode = "inspection", message = "Maintenance" }))
    ccunit.contains(rows()[1], "INSPECTION SERVICE")
    ccunit.eq(bg(2, 1), colors.orange)
    ccunit.eq(fg(18, 1), colors.black)
    ccunit.truthy(countBg(5, 1, 26, colors.orange) >= 3, "floor is amber")
    ccunit.eq(fg(14, 9), colors.orange)
  end)
end, { timeout = 10 })

ccunit.test("a long floor name still fits (L1)", function()
  setup()
  with(function()
    feed(state({ floor = "L1" }))
    ccunit.truthy(countBg(7, 1, 26, colors.white) >= 5)
  end)
end, { timeout = 10 })

ccunit.test("chime: once for 1, twice for 2, queued ones are not lost", function()
  setup()
  with(function()
    feed({ type = "chime", car = "A", count = 1 }, 1)
    ccunit.eq(count("note", "bell"), 1)
    feed({ type = "chime", car = "A", count = 2 }, 1.6)
    ccunit.eq(count("note", "bell"), 3)
    feed({ type = "chime", car = "A", count = 1 }, 0)
    feed({ type = "chime", car = "A", count = 2 }, 3)
    ccunit.eq(count("note", "bell"), 6)
    feed({ type = "chime", car = "B", count = 2 }, 1.5) -- the other car's
    ccunit.eq(count("note", "bell"), 6)
  end)
end, { timeout = 20 })

ccunit.test("music plays on 'play' and ducks while chiming", function()
  setup()
  with(function()
    feed({ type = "music", car = "A", cmd = "play" }, 1.5)
    ccunit.truthy(count("audio") >= 1, "playing")
    ccunit.truthy(music.isPlaying())
    log = {}
    feed({ type = "chime", car = "A", count = 2 }, 0.3)
    ccunit.eq(music.isPlaying(), false, "ducked while chiming")
    sleep(2.5)
    local firstBell, lastBell
    for _, e in ipairs(log) do
      if e.k == "note" and e.inst == "bell" then firstBell = firstBell or e.t; lastBell = e.t end
    end
    ccunit.truthy(firstBell, "chimed")
    for _, e in ipairs(log) do
      if e.k == "audio" then ccunit.truthy(e.t < firstBell - 0.01 or e.t > lastBell, "no music audio during the chime") end
    end
    ccunit.truthy(count("stop") >= 1, "speaker stopped for the chime")
    ccunit.truthy(music.isPlaying(), "music is back")
    local n = count("audio")
    sleep(1.5)
    ccunit.truthy(count("audio") > n, "audio flows again")
  end)
end, { timeout = 25 })

ccunit.test("hub duck / resume and stop", function()
  setup()
  with(function()
    feed({ type = "music", car = "A", cmd = "play" }, 1)
    feed({ type = "music", car = "A", cmd = "duck" }, 0.3)
    ccunit.eq(music.isPlaying(), false)
    feed({ type = "music", car = "A", cmd = "resume" }, 0.3)
    ccunit.truthy(music.isPlaying())
    feed({ type = "music", car = "A", cmd = "stop" }, 0.3)
    ccunit.eq(music.isPlaying(), false)
    ccunit.eq(cab.S.wantMusic, false)
  end)
end, { timeout = 15 })

ccunit.test("alarm sounds while on, ducks the music, stops when off", function()
  setup()
  with(function()
    feed({ type = "music", car = "A", cmd = "play" }, 1)
    feed({ type = "alarm", car = "A", on = true }, 1.5)
    ccunit.truthy(count("note", "pling") >= 3, "alarm notes: " .. count("note", "pling"))
    ccunit.eq(music.isPlaying(), false, "music ducked")
    feed({ type = "alarm", car = "A", on = false }, 0.8)
    local n = count("note", "pling")
    sleep(1)
    ccunit.eq(count("note", "pling"), n, "silent after off")
    ccunit.truthy(music.isPlaying(), "music resumes")
  end)
end, { timeout = 20 })

ccunit.test("fire, emergency and lockdown stop the music; normal brings it back", function()
  setup()
  with(function()
    feed({ type = "music", car = "A", cmd = "play" }, 1)
    for _, mode in ipairs({ "fire_recall", "fire_hold", "firefighter", "emergency", "lockdown_trapped" }) do
      feed(state({ mode = mode }), 0.3)
      ccunit.eq(music.isPlaying(), false, mode)
    end
    feed(state({ mode = "normal" }), 0.3)
    ccunit.truthy(music.isPlaying(), "music back in normal")
    feed(state({ mode = "inspection" }), 0.3)
    ccunit.truthy(music.isPlaying(), "inspection keeps it")
  end)
end, { timeout = 20 })

ccunit.test("hub silence: Out of Order, positions keep going, state brings it back", function()
  setup(1.5)
  with(function()
    feed(state({ floor = "3", dir = "up", doors = "open", next = "5" }))
    ccunit.contains(rows()[1], "MOONLIFT")
    sleep(2.2)
    local r = rows()
    ccunit.contains(r[1], "OUT OF ORDER")
    ccunit.contains(r[9], "Out of Order")
    ccunit.eq(fg(14, 9), colors.red)
    ccunit.eq(countBg(4, 27, 36, colors.lime), 0, "no arrow")
    local n = #ofType("pos")
    sleep(1)
    ccunit.truthy(#ofType("pos") >= n + 8, "positions keep flowing in silence")
    feed(state({ floor = "5" }))
    ccunit.contains(rows()[1], "MOONLIFT")
  end)
end, { timeout = 15 })

ccunit.test("silence stops music and alarm", function()
  setup(1)
  with(function()
    feed(state())
    feed({ type = "music", car = "A", cmd = "play" }, 0.5)
    feed({ type = "alarm", car = "A", on = true }, 0.3)
    sleep(1.8)
    ccunit.eq(music.isPlaying(), false)
    local n = count("note", "pling")
    sleep(1)
    ccunit.eq(count("note", "pling"), n)
  end)
end, { timeout = 15 })

ccunit.test("positions: about 10 a second, y and t, err when GPS fails", function()
  setup()
  with(function()
    sleep(2)
    local p = ofType("pos")
    ccunit.truthy(#p >= 17 and #p <= 22, "count " .. #p)
    ccunit.eq(p[1].y, 100.25)
    ccunit.eq(p[1].car, "A")
    ccunit.truthy(type(p[1].t) == "number")
    fakeY = nil
    sleep(0.5)
    local last = ofType("pos")
    last = last[#last]
    ccunit.eq(last.y, nil)
    ccunit.eq(last.err, "nogps")
  end)
end, { timeout = 10 })

ccunit.test("positions keep flowing while music and chimes play", function()
  setup()
  with(function()
    feed({ type = "music", car = "A", cmd = "play" }, 0.5)
    local t0 = os.clock()
    for i = 1, 3 do os.queueEvent("rednet_message", 9, { type = "chime", car = "A", count = 2 }, "mmlift") end
    feed({ type = "alarm", car = "A", on = true }, 0)
    for i = 1, 60 do
      os.queueEvent("rednet_message", 9, state({ floor = "G", dir = "up" }), "mmlift")
      sleep(0.05)
    end
    sleep(2)
    local gap, prev = 0, nil
    for _, m in ipairs(ofType("pos")) do
      if m.at >= t0 then
        if prev then gap = math.max(gap, m.at - prev) end
        prev = m.at
      end
    end
    ccunit.truthy(gap > 0 and gap < 0.25, "largest gap between positions " .. gap)
    ccunit.eq(count("note", "bell"), 6, "all chimes played")
    ccunit.truthy(count("note", "pling") > 3, "alarm ran")
  end)
end, { timeout = 20 })

ccunit.test("door state comes from the redstone level on the left: 15 open, 8 closed, else fault", function()
  setup()
  local level = 8
  cab.doorLevel = function() return level end
  with(function()
    local function last() local d = ofType("door_state"); return d[#d] end
    sleep(0.4)
    ccunit.eq(last().open, false); ccunit.eq(last().ok, true); ccunit.eq(last().car, "A")
    level = 15; sleep(0.4)
    ccunit.eq(last().open, true); ccunit.eq(last().ok, true)
    level = 0; sleep(0.4)
    ccunit.eq(last().ok, false, "0 is a fault")
    level = 11; sleep(0.4)
    ccunit.eq(last().ok, false, "other levels are a fault")
    level = 8
    -- every second even without a change
    sleep(0.3)
    local n = #ofType("door_state")
    sleep(2.1)
    ccunit.truthy(#ofType("door_state") >= n + 2, "repeats each second")
  end)
  cab.doorLevel = realDoorLevel
end, { timeout = 20 })

ccunit.test("door side defaults to left and reads the real redstone input", function()
  setup()
  ccunit.eq(cab.config.doorSide, "left")
  cab.doorLevel = realDoorLevel
  local real = redstone.getAnalogInput
  local asked
  redstone.getAnalogInput = function(side) asked = side; return 15 end
  with(function()
    sleep(0.4)
    local d = ofType("door_state")
    ccunit.eq(d[#d].open, true)
  end)
  redstone.getAnalogInput = real
  ccunit.eq(asked, "left")
end, { timeout = 10 })

ccunit.test("doorsensor.lua: 15 open, 8 closed, 0 when the reader is missing or fails", function()
  setup()
  local states = { open = true }
  local fail = false
  local function mk()
    return { getBlockStates = function() if fail then error("boom") end return states end }
  end
  local function level() return redstone.getAnalogOutput("top") end
  parallel.waitForAny(function() dofile("doorsensor.lua") end, function()
    reader = nil; sleep(0.3)
    ccunit.eq(level(), 0, "no reader")
    reader = mk(); sleep(0.3)
    ccunit.eq(level(), 15, "open")
    states = { open = false }; sleep(0.3)
    ccunit.eq(level(), 8, "closed")
    fail = true; sleep(0.3)
    ccunit.eq(level(), 0, "read fails")
    fail = false; states = nil; sleep(0.3)
    ccunit.eq(level(), 0, "no state")
    states = { open = true }; sleep(0.3)
    ccunit.eq(level(), 15, "back")
  end)
end, { timeout = 15 })

ccunit.test("messages for the other car are ignored", function()
  setup()
  with(function()
    feed(state({ floor = "G" }))
    feed({ type = "state", car = "B", floor = "6", mode = "fire_recall" })
    ccunit.eq(cab.view().floor, "G")
    ccunit.eq(cab.view().mode, "normal")
  end)
end, { timeout = 10 })

peripheral.find = realFind
