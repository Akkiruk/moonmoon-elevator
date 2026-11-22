-- Run from this folder: craftos-mcp test --world cab.world.json
-- Ogg track folders. The emulator has no cc-audio-expand, so speaker.playAudioEx and cc.audio.ogg are faked; each
-- fake speaker keeps one packet waiting and sends it like the mod's server side does.
local music = require "music"

local realFind = peripheral.find
local calls, stops, volumes, sizes, srvs

-- n: how many speakers with playAudioEx (0 = the emulator's own speaker only)
local function spy(n)
  calls, stops, volumes, sizes, srvs = 0, 0, {}, {}, {}
  local sp = realFind("speaker")
  local list = {}
  for i = 1, math.max(n, 1) do
    local fake = setmetatable({
      playAudio = function(buf, vol)
        local ok = sp.playAudio(buf, vol)
        if ok then calls = calls + 1; volumes[#volumes + 1] = vol; sizes[#sizes + 1] = #buf end
        return ok
      end,
      stop = function() stops = stops + 1; return sp.stop() end,
    }, { __index = sp })
    if n > 0 then
      -- cc-audio-expand's server side: one packet waits, and it goes out once the client is down to half a
      -- second (as the server counts it). serverTick() sends it and records when, like the mod's update.
      local srv = { pending = nil, ends = 0, sent = {} }
      srvs[i] = srv
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
    list[i] = fake
  end
  peripheral.find = function(t)
    if t == "speaker" then return table.unpack(list) end
    return realFind(t)
  end
end

-- the fake decoder repeats the file's character out to the length list.txt asks for, with "<" in front (the part
-- to skip) and ">" behind (the padding the real decoder leaves)
local decodes
local function fakeOgg(on)
  package.loaded["cc.audio.ogg"] = nil
  package.preload["cc.audio.ogg"] = on and function()
    return {
      decode = function(data)
        decodes = decodes + 1
        local ch, skip, keep = data:match("^(.) (%d+) (%d+)$")
        return ("<"):rep(skip * 2) .. ch:rep(keep * 2) .. (">"):rep(1354),
          { format = "pcm_s16le", sampleRate = 48000, channels = 1 }
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

local f = fs.open("/t3.dfpwm", "wb")
for _ = 1, 2 do f.write(string.rep("\x55\xAA", 4050)) end
f.close()

local function serverTick()
  while true do
    sleep(0.05)
    local now = os.epoch("utc")
    for i, srv in ipairs(srvs) do
      if srv.pending and now >= srv.ends - 500 then
        local s = srv.pending
        srv.pending = nil
        srv.sent[#srv.sent + 1] = { t = now, s = s, sp = i }
        srv.ends = math.max(now, srv.ends) + #s / 96
        calls = calls + 1
        os.queueEvent("speaker_audio_empty", "right")
      end
    end
  end
end

local function with(scenario)
  parallel.waitForAny(music.run, function() scenario() end, serverTick)
end

-- the music packets the fake speakers sent, in time order (the silent ones are all zero bytes)
local function musicSent()
  local out = {}
  for _, srv in ipairs(srvs) do
    for _, p in ipairs(srv.sent) do
      if p.s:find("[^%z]") then out[#out + 1] = p end
    end
  end
  table.sort(out, function(x, y) return x.t < y.t end)
  return out
end

local P = 129600 -- bytes in a 1.35 s packet

ccunit.test("one speaker: 16-bit 1.35 s packets, each part cut to its length, looping without a break", function()
  spy(1)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 70000 }, { "b", 4096, 100000 }, { "c", 4096, 5000 } })
  music.setVolume(0.5)
  local pass = ("a"):rep(140000) .. ("b"):rep(200000) .. ("c"):rep(10000)
  with(function()
    music.play("/song")
    local t = os.clock() + 15
    while #musicSent() < 6 and os.clock() < t do sleep(0.1) end
  end)
  music.stop(); music.setVolume(1)
  local m = musicSent()
  local got = {}
  for i = 1, 5 do got[i] = m[i].s end
  got = table.concat(got)
  ccunit.eq(got, (pass .. pass):sub(1, 5 * P), "the song, then straight into it again")
  ccunit.eq(#srvs[1].sent[1].s, 50400, "the silent packet first")
  for i = 2, #m do
    ccunit.eq(#m[i].s, P)
    local gap = m[i].t - m[i - 1].t
    ccunit.truthy(math.abs(gap - 1350) <= 60, "packet " .. i .. " came " .. gap .. " ms after the last")
  end
  ccunit.eq(volumes[1], 0.5)
end, { timeout = 30 })

local function samples(s, from, n)
  return { string.unpack("<" .. ("i2"):rep(n), s, from * 2 - 1) }
end

ccunit.test("two speakers: packets alternate, every 1.2 s, and the 0.15 s overlaps add back to the music", function()
  spy(2)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 48000 * 12 }, { "b", 0, 48000 * 12 } })
  with(function()
    music.play("/song")
    sleep(10)
  end)
  music.stop()
  local m = musicSent()
  ccunit.truthy(#m >= 6, "sent " .. #m)
  ccunit.eq(#srvs[1].sent[1].s, 50400, "speaker 1 starts with the silent packet")
  ccunit.eq(#srvs[2].sent[1].s, 50400, "speaker 2 too")
  ccunit.eq(srvs[1].sent[1].t, srvs[2].sent[1].t, "in the same tick")
  local value = ("<i2"):unpack("aa")
  for i = 1, #m do
    ccunit.eq(#m[i].s, P, "packet " .. i)
    ccunit.eq(m[i].sp, (i - 1) % 2 + 1, "packet " .. i .. " on the other speaker")
    if i > 1 then
      local gap = m[i].t - m[i - 1].t
      ccunit.truthy(math.abs(gap - 1200) <= 60, "packet " .. i .. " came " .. gap .. " ms after the last")
      local tailOf, headOf = samples(m[i - 1].s, 64800 - 7200 + 1, 200), samples(m[i].s, 1, 200)
      for j = 1, 200 do
        ccunit.truthy(math.abs(tailOf[j] + headOf[j] - value) <= 1, "overlap " .. i .. " sample " .. j)
      end
    end
  end
  ccunit.truthy(samples(m[1].s, 1, 1)[1] < 100, "the very first packet fades in")
  local mid = samples(m[2].s, 30000, 1)[1]
  ccunit.eq(mid, value, "the middle of a packet is untouched")
end, { timeout = 30 })

ccunit.test("two speakers: duck stops both, then both start again together", function()
  spy(2)
  fakeOgg(true)
  decodes = 0
  writeTrack("/song", { { "a", 0, 48000 * 30 } })
  local before, during
  with(function()
    music.play("/song")
    sleep(4)
    music.duck(true); sleep(0.3)
    before = calls
    sleep(2)
    during = calls
    music.duck(false); sleep(3)
  end)
  music.stop()
  ccunit.eq(during, before, "silent while ducked")
  ccunit.truthy(stops >= 4, "both speakers stopped, stops=" .. stops)
  ccunit.truthy(calls > during, "plays again after duck(false)")
  local function leadsAfter(srv)
    for _, p in ipairs(srv.sent) do
      if p.t > srvs[1].sent[1].t + 4000 and #p.s == 50400 then return p.t end
    end
  end
  local a, b = leadsAfter(srvs[1]), leadsAfter(srvs[2])
  ccunit.truthy(a and b and a == b, "both silent packets again, same tick")
  ccunit.eq(decodes, 1, "the part was not decoded again")
end, { timeout = 20 })

ccunit.test("ogg track without cc-audio-expand: the fallback plays instead", function()
  spy(0)
  fakeOgg(false)
  writeTrack("/song", { { "a", 0, 1000 } })
  with(function()
    music.play("/song", { fallback = "/t3.dfpwm" })
    sleep(1)
  end)
  music.stop()
  ccunit.truthy(calls >= 1 and #sizes >= 1, "fallback dfpwm played, calls=" .. calls)
end, { timeout = 10 })
