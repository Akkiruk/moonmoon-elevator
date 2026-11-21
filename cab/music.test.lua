-- Run from this folder: craftos-mcp test --world cab.world.json
-- The test feeds the player small files it writes itself (CHUNK = 8192 bytes of DFPWM), and spies on the speaker.
-- The emulator has no cc-audio-expand, so its playAudioEx and cc.audio.ogg are faked for the Ogg tests.
-- http is not tested: the emulator has no network, so URL sources are untested here.
local music = require "music"
local dfpwm = require "cc.audio.dfpwm"

local realFind = peripheral.find
local calls, stops, volumes, sizes, packets
local function spy(withEx)
  calls, stops, volumes, sizes, packets = 0, 0, {}, {}, {}
  local sp = realFind("speaker")
  local fake = setmetatable({
    playAudio = function(buf, vol)
      local ok = sp.playAudio(buf, vol)
      if ok then calls = calls + 1; volumes[#volumes + 1] = vol; sizes[#sizes + 1] = #buf end
      return ok
    end,
    stop = function() stops = stops + 1; return sp.stop() end,
  }, { __index = sp })
  if withEx then
    -- roughly like the mod: the call takes a tick, and the next packet is refused until the client is down to
    -- half a second of audio
    local busyUntil = 0
    fake.playAudioEx = function(s, opts)
      sleep(0.05)
      local now = os.epoch("utc")
      if now < busyUntil - 500 then
        os.queueEvent("speaker_audio_empty", "right")
        return false
      end
      busyUntil = math.max(now, busyUntil) + #s / 96
      calls = calls + 1
      packets[#packets + 1] = s
      volumes[#volumes + 1] = opts.volume
      ccunit.eq(opts.format, "pcm_s16le")
      return true
    end
  end
  peripheral.find = function(t) if t == "speaker" then return fake end return realFind(t) end
end

-- the fake decoder returns the file's text repeated out to the length list.txt asks for, with "<" in front
-- (the part to skip) and ">" behind (the padding the real decoder leaves)
local decodes
local function fakeOgg(on)
  package.loaded["cc.audio.ogg"] = nil
  package.preload["cc.audio.ogg"] = on and function()
    return {
      decode = function(data)
        decodes = decodes + 1
        local ch, skip, keep = data:match("^(.) (%d+) (%d+)$")
        local pcm = ("<"):rep(skip * 2) .. ch:rep(keep * 2) .. (">"):rep(1354)
        return pcm, { format = "pcm_s16le", sampleRate = 48000, channels = 1 }
      end,
    }
  end or nil
end

local function writeTrack(dir, parts)
  fs.makeDir(dir)
  local list = fs.open(dir .. "/list.txt", "w")
  for i, p in ipairs(parts) do
    local name = ("%02d.ogg"):format(i)
    local f = fs.open(dir .. "/" .. name, "w")
    f.write(p[1] .. " " .. p[2] .. " " .. p[3])
    f.close()
    list.writeLine(name .. " " .. p[2] .. " " .. p[3])
  end
  list.close()
end

local function write(path, chunks)
  local f = fs.open(path, "wb")
  for _ = 1, chunks do f.write(string.rep("\x55\xAA", 4096)) end
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
    sleep(5) -- each chunk is 1.37 s of audio: 2 chunks per pass, so more than 2 calls means it looped
  end)
  ccunit.truthy(calls > 2, "looped, calls=" .. calls)
  for i, n in ipairs(sizes) do ccunit.eq(n, 65536, "chunk " .. i) end
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

-- Half-rate files (name.24k.dfpwm): 4096 bytes = 32768 samples at 24 kHz, played as 65536 at 48 kHz.
ccunit.test("half rate: upsampled to 65536 samples per chunk, loops, ducks, stops", function()
  spy()
  local f = fs.open("/h.24k.dfpwm", "wb")
  for _ = 1, 2 do f.write(string.rep(string.char(0x55, 0xAA), 2048)) end
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
  for i, n in ipairs(sizes) do ccunit.eq(n, 65536, "chunk " .. i .. " of " .. table.concat(sizes, ",")) end
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
  -- playAudio itself holds the computer ~75 ms for 65536 samples here, so one beat can slip a tick; the hub's
  -- lost-position limit is 0.5 s
  ccunit.truthy(worst <= 0.25, "the 10 Hz loop waited " .. worst .. " s")
  ccunit.truthy(music.lastPiece and music.lastPiece < 0.1, "a piece took " .. tostring(music.lastPiece) .. " s")
end, { timeout = 15 })

ccunit.test("ogg track: every part cut to its length, in order, in packets the mod takes, then loops", function()
  spy(true)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 70000 }, { "b", 4096, 100000 }, { "c", 4096, 5000 } })
  music.setVolume(2)
  local pass = ("a"):rep(140000) .. ("b"):rep(200000) .. ("c"):rep(10000)
  with(function()
    music.play("/song")
    local t = os.clock() + 15
    while #table.concat(packets) <= #pass + 10 and os.clock() < t do sleep(0.1) end
  end)
  music.stop(); music.setVolume(1)
  local all = table.concat(packets)
  ccunit.eq(all:sub(1, #pass), pass, "first pass is exactly the kept audio")
  ccunit.eq(all:sub(#pass + 1, #pass + 10), ("a"):rep(10), "then it starts again")
  for i, p in ipairs(packets) do ccunit.truthy(#p <= 131072, "packet " .. i .. " is " .. #p .. " bytes") end
  ccunit.eq(volumes[1], 2)
end, { timeout = 25 })

ccunit.test("ogg track: duck stops the speaker and resumes where it was", function()
  spy(true)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 48000 * 8 } })
  local atDuck, afterWait
  with(function()
    music.play("/song")
    sleep(1.5)
    music.duck(true); sleep(0.2)
    atDuck = calls
    sleep(2)
    afterWait = calls
    music.duck(false); sleep(1.5)
  end)
  music.stop()
  ccunit.truthy(atDuck >= 1, "it played first")
  ccunit.eq(afterWait, atDuck, "silent while ducked")
  ccunit.truthy(stops >= 1, "speaker.stop called")
  ccunit.truthy(calls > atDuck, "plays again after duck(false)")
  ccunit.eq(decodes, 1, "the part was not decoded again")
end, { timeout = 15 })

ccunit.test("ogg track without cc-audio-expand: the fallback plays instead", function()
  spy(false)
  fakeOgg(false)
  writeTrack("/song", { { "a", 0, 1000 } })
  with(function()
    music.play("/song", { fallback = "/t3.dfpwm" })
    sleep(1)
  end)
  music.stop()
  ccunit.truthy(calls >= 1 and #sizes >= 1, "fallback dfpwm played, calls=" .. calls)
end, { timeout = 10 })

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
