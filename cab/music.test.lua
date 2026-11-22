-- Run from this folder: craftos-mcp test --world cab.world.json
-- The test feeds the player small files it writes itself (CHUNK = 8100 bytes of DFPWM), and spies on the speaker.
-- Ogg track folders are tested in music_ogg.test.lua.
-- http is not tested: the emulator has no network, so URL sources are untested here.
local music = require "music"
local dfpwm = require "cc.audio.dfpwm"

local realFind = peripheral.find
local calls, stops, volumes, sizes
local function spy()
  calls, stops, volumes, sizes = 0, 0, {}, {}
  local sp = realFind("speaker")
  local fake = setmetatable({
    playAudio = function(buf, vol)
      local ok = sp.playAudio(buf, vol)
      if ok then calls = calls + 1; volumes[#volumes + 1] = vol; sizes[#sizes + 1] = #buf end
      return ok
    end,
    stop = function() stops = stops + 1; return sp.stop() end,
  }, { __index = sp })
  peripheral.find = function(t) if t == "speaker" then return fake end return realFind(t) end
end

local function write(path, chunks)
  local f = fs.open(path, "wb")
  for _ = 1, chunks do f.write(string.rep("\x55\xAA", 4050)) end
  f.close()
end

-- run music.run beside a scenario; return when the scenario returns
local function with(scenario)
  parallel.waitForAny(music.run, function() scenario() end)
end

ccunit.test("the fast decoder matches cc.audio.dfpwm", function()
  local f = fs.open("/tracks/sins/01.ogg", "rb") -- any bytes will do
  local s = f.read(20000)
  f.close()
  local want = dfpwm.make_decoder()(s)
  local got = {}
  local dec = music.decoder()
  local n = 0
  for i = 1, #s, 333 do n = dec(s:sub(i, i + 332), got, n) end -- pieces, so the state carries over
  ccunit.eq(n, #want)
  for i = 1, #want do
    if got[i] ~= want[i] then error("sample " .. i .. ": " .. got[i] .. " vs " .. want[i]) end
  end
end, { timeout = 30 })

ccunit.test("feeds the whole file, then loops", function()
  spy()
  write("/t3.dfpwm", 2)
  music.setVolume(1)
  with(function()
    music.play("/t3.dfpwm")
    sleep(5) -- the silent packet, then 2 chunks of 1.35 s per pass, so more than 3 calls means it looped
  end)
  ccunit.truthy(calls > 3, "looped, calls=" .. calls)
  ccunit.eq(sizes[1], 25200, "starts with the silent packet")
  for i = 2, #sizes do ccunit.eq(sizes[i], 64800, "chunk " .. i) end
  music.stop()
end, { timeout = 20 })

ccunit.test("volume is passed to the speaker", function()
  spy()
  with(function()
    music.setVolume(0.5)
    music.play("/t3.dfpwm")
    sleep(1)
  end)
  ccunit.eq(volumes[1], 0.5)
  music.stop(); music.setVolume(1)
end, { timeout = 10 })

ccunit.test("stop() halts it", function()
  spy()
  local before
  with(function()
    music.play("/t3.dfpwm")
    sleep(2)
    music.stop()
    sleep(0.2)
    before = calls
    sleep(3)
  end)
  ccunit.truthy(before >= 1, "it played first")
  ccunit.eq(calls, before)
  ccunit.truthy(stops >= 1, "speaker.stop called")
  ccunit.eq(music.isPlaying(), false)
end, { timeout = 15 })

ccunit.test("duck pauses and resumes", function()
  spy()
  local atDuck, afterWait
  with(function()
    music.play("/t3.dfpwm")
    sleep(2)
    music.duck(true)
    sleep(0.2)
    atDuck = calls
    sleep(3)
    afterWait = calls
    music.duck(false)
    sleep(2)
  end)
  ccunit.eq(afterWait, atDuck, "silent while ducked")
  ccunit.truthy(calls > atDuck, "plays again after duck(false)")
  music.stop()
end, { timeout = 20 })

ccunit.test("survives other events", function()
  spy()
  with(function()
    music.play("/t3.dfpwm")
    for i = 1, 20 do
      os.queueEvent("rednet_message", 1, "x", "p")
      os.queueEvent("timer", 9999 + i)
      os.queueEvent("key", 65)
      sleep(0.1)
    end
    music.duck(true); music.duck(false)
    sleep(1)
  end)
  ccunit.truthy(calls >= 2, "kept feeding, calls=" .. calls)
  music.stop()
end, { timeout = 20 })

ccunit.test("missing source and fallback: waits, then the fallback is used", function()
  spy()
  with(function()
    music.play("/nope.dfpwm", { fallback = "/t3.dfpwm" })
    sleep(1)
  end)
  ccunit.truthy(calls >= 1, "fallback played")
  music.stop()
end, { timeout = 10 })

ccunit.test("play() switches track", function()
  spy()
  write("/other.dfpwm", 1)
  with(function()
    music.play("/t3.dfpwm"); sleep(1)
    music.play("/other.dfpwm"); sleep(3)
  end)
  ccunit.truthy(calls >= 3, "calls=" .. calls)
  music.stop()
end, { timeout = 15 })

-- Half-rate files (name.24k.dfpwm): 4050 bytes = 32400 samples at 24 kHz, played as 64800 at 48 kHz.
ccunit.test("half rate: upsampled to 64800 samples per chunk, loops, ducks, stops", function()
  spy()
  local f = fs.open("/h.24k.dfpwm", "wb")
  for _ = 1, 2 do f.write(string.rep(string.char(0x55, 0xAA), 2025)) end
  f.close()
  local atDuck, atStop
  with(function()
    music.play("/h.24k.dfpwm")
    sleep(5)
    music.duck(true); sleep(0.3); atDuck = calls; sleep(2)
    ccunit.eq(calls, atDuck, "silent while ducked")
    music.duck(false); sleep(1)
    music.stop(); sleep(0.3); atStop = calls; sleep(2)
  end)
  ccunit.truthy(atDuck > 2, "looped, calls=" .. atDuck)
  for i, n in ipairs(sizes) do
    ccunit.truthy(n == 64800 or n == 25200, "chunk " .. i .. " of " .. table.concat(sizes, ","))
  end
  ccunit.truthy(atStop > atDuck, "resumed after the duck")
  ccunit.eq(calls, atStop, "stopped")
end, { timeout = 20 })

ccunit.test("dfpwm: one piece's decode is cheap and a 10 Hz loop beside it keeps its pace", function()
  spy()
  write("/t6.dfpwm", 6)
  local worst, last = 0, nil
  parallel.waitForAny(music.run, function()
    music.play("/t6.dfpwm")
    local stop = os.clock() + 4
    while os.clock() < stop do
      local now = os.clock()
      if last then worst = math.max(worst, now - last) end
      last = now
      sleep(0.1)
    end
  end)
  music.stop()
  ccunit.truthy(calls >= 2, "calls=" .. calls)
  -- playAudio itself holds the computer ~75 ms for 64800 samples here, so one beat can slip a tick; the hub's
  -- lost-position limit is 0.5 s
  ccunit.truthy(worst <= 0.25, "the 10 Hz loop waited " .. worst .. " s")
  ccunit.truthy(music.lastPiece and music.lastPiece < 0.1, "a piece took " .. tostring(music.lastPiece) .. " s")
end, { timeout = 15 })

ccunit.test("no speaker: the player waits instead of spinning, and a loop beside it keeps running", function()
  peripheral.find = function(t) if t == "speaker" then return nil end return realFind(t) end
  local ticks = 0
  parallel.waitForAny(music.run, function()
    music.play("/t3.dfpwm")
    for _ = 1, 30 do sleep(0.1); ticks = ticks + 1 end
  end)
  music.stop()
  ccunit.eq(ticks, 30, "the other loop got all its turns")
end, { timeout = 15 })

ccunit.test("the real Sins track is all there and fits the cab's 1 MB disk with the code", function()
  local list = fs.open("/tracks/sins/list.txt", "r")
  local samples, used = 0, 0
  for line in list.readLine do
    local name, _, keep = line:match("^(%S+) (%d+) (%d+)$")
    ccunit.truthy(fs.exists("/tracks/sins/" .. name), name)
    samples = samples + tonumber(keep)
  end
  list.close()
  ccunit.truthy(math.abs(samples / 48000 - 171.75) < 0.05, "plays " .. samples / 48000 .. " s of 171.75")
  -- CC counts every file and folder as at least 500 bytes
  local function size(p) return math.max(500, fs.getSize(p)) end
  for _, f in ipairs(fs.list("/tracks/sins")) do used = used + size("/tracks/sins/" .. f) end
  for _, f in ipairs({ "cab.lua", "music.lua", "play.lua", "startup.lua" }) do used = used + size("/" .. f) end
  used = used + 500 * 3 -- car.txt and the two folders
  ccunit.truthy(used < 950000, "uses " .. used .. " bytes, keep some room for the code to grow")
end, { timeout = 10 })
