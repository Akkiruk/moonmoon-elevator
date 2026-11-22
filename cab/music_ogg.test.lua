-- Run from this folder: craftos-mcp test --world cab.world.json
-- Ogg track folders. The emulator has no cc-audio-expand, so speaker.playAudioEx and cc.audio.ogg are faked; the
-- fake speaker keeps one packet waiting and sends it like the mod's server side does.
local music = require "music"

local realFind = peripheral.find
local calls, stops, volumes, sizes, srv
local function spy(withEx)
  calls, stops, volumes, sizes, srv = 0, 0, {}, {}, nil
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
    -- cc-audio-expand's server side: one packet waits, and it goes out once the client is down to half a second
    -- (as the server counts it). serverTick() below sends it and records when, like the mod's update.
    srv = { pending = nil, ends = 0, sent = {} }
    fake.playAudioEx = function(s, opts)
      sleep(0.05) -- runs on the main thread: a tick
      ccunit.eq(opts.format, "pcm_s16le")
      if srv.pending then return false end
      srv.pending = s
      volumes[#volumes + 1] = opts.volume
      return true
    end
    fake.stop = function() stops = stops + 1; srv.pending = nil; srv.ends = os.epoch("utc") end
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
  for _ = 1, chunks do f.write(string.rep("\x55\xAA", 4050)) end
  f.close()
end
write("/t3.dfpwm", 2)

local function serverTick()
  while true do
    sleep(0.05)
    local now = os.epoch("utc")
    if srv.pending and now >= srv.ends - 500 then
      local s = srv.pending
      srv.pending = nil
      srv.sent[#srv.sent + 1] = { t = now, s = s }
      srv.ends = math.max(now, srv.ends) + #s / 96
      calls = calls + 1
      os.queueEvent("speaker_audio_empty", "right")
    end
  end
end

-- run music.run beside a scenario; return when the scenario returns
local function with(scenario)
  if srv then
    parallel.waitForAny(music.run, function() scenario() end, serverTick)
  else
    parallel.waitForAny(music.run, function() scenario() end)
  end
end

-- the music packets the fake server sent (the silent ones are all zero bytes)
local function music_sent()
  local out = {}
  for _, p in ipairs(srv.sent) do
    if p.s:find("[^%z]") then out[#out + 1] = p end
  end
  return out
end

ccunit.test("ogg track: every part cut to its length, in order, in full 1.35 s packets, then loops", function()
  spy(true)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 70000 }, { "b", 4096, 100000 }, { "c", 4096, 5000 } })
  music.setVolume(2)
  local pass = ("a"):rep(140000) .. ("b"):rep(200000) .. ("c"):rep(10000)
  local function sent()
    local t = {}
    for i, p in ipairs(music_sent()) do t[i] = p.s end
    return table.concat(t)
  end
  with(function()
    music.play("/song")
    local t = os.clock() + 15
    while #sent() <= 3 * 129600 + 10 and os.clock() < t do sleep(0.1) end
  end)
  music.stop(); music.setVolume(1)
  local all = sent()
  -- 350000 bytes is 2.7 packets: the last one is padded with silence, then the next pass starts
  ccunit.eq(all:sub(1, #pass), pass, "first pass is exactly the kept audio")
  ccunit.eq(all:sub(#pass + 1, 3 * 129600), ("\0"):rep(3 * 129600 - #pass), "padded to a whole packet")
  ccunit.eq(all:sub(3 * 129600 + 1, 3 * 129600 + 10), ("a"):rep(10), "then it starts again")
  for i, p in ipairs(srv.sent) do
    ccunit.truthy(#p.s == 129600 or (i == 1 and #p.s == 50400), "packet " .. i .. " is " .. #p.s .. " bytes")
  end
  ccunit.eq(volumes[1], 2)
end, { timeout = 30 })

-- On a sub-level every packet starts the moment it reaches the client, so the send times are the audio's timing.
ccunit.test("ogg track: each packet goes out as the last one ends, with no overlap", function()
  spy(true)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 48000 * 12 } })
  with(function()
    music.play("/song")
    sleep(9)
  end)
  music.stop()
  local m = music_sent()
  ccunit.truthy(#m >= 5, "sent " .. #m)
  ccunit.eq(#srv.sent[1].s, 50400, "the silent packet goes first")
  ccunit.truthy(m[1].t - srv.sent[1].t <= 120, "music starts right after it: " .. (m[1].t - srv.sent[1].t) .. " ms")
  for i = 2, #m do
    local gap = m[i].t - m[i - 1].t
    ccunit.truthy(math.abs(gap - 1350) <= 60, "packet " .. i .. " came " .. gap .. " ms after the last (1350 wanted)")
  end
end, { timeout = 20 })

ccunit.test("ogg track: duck stops the speaker, then it starts clean where it was", function()
  spy(true)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 48000 * 30 } })
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
  ccunit.truthy(atDuck >= 2, "it played first")
  ccunit.eq(afterWait, atDuck, "silent while ducked")
  ccunit.truthy(stops >= 1, "speaker.stop called")
  ccunit.truthy(calls > atDuck, "plays again after duck(false)")
  ccunit.eq(#srv.sent[atDuck + 1].s, 50400, "the silent packet goes first again")
  ccunit.eq(decodes, 1, "the part was not decoded again ")
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
