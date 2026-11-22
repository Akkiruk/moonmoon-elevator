-- Looping music player for the cab speaker.
--
--   local music = require "music"
--   music.play("/tracks/sins")   -- a track folder, a .dfpwm file or an http URL; { fallback = path } is optional
--   parallel.waitForAny(music.run, display, rednetLoop)
--
-- music.run() is the player loop: run it beside your other code, it only reacts to events.
-- The other functions just change settings and wake it, so call them from anywhere.
--
-- A track folder is Ogg Vorbis parts plus list.txt (tools/to-ogg.mjs makes one). It needs the cc-audio-expand mod:
-- cc.audio.ogg decodes a part in Java and speaker.playAudioEx takes the 16-bit samples as a string, so Lua never
-- touches a sample. DFPWM files are decoded here in Lua instead, which costs real CPU on a shared computer thread.
--
-- Why every packet is exactly 1.35 s and playback starts with a short silent packet: the cab is on a Sable
-- sub-level. Sable wraps each sound played there in its own object, so the speaker's client code never finds its
-- sound again (isActive is always false) and every packet starts as a new sound the moment it arrives. The server
-- sends a packet 0.5 s before it thinks the last one ends, so packets overlapped by half a second and the old one's
-- cleanup wiped the new one's queue. The silent packet is 0.525 s, which puts the server's clock 0.5 s ahead
-- of the real audio, so from then on each packet arrives as the last one ends; 1.35 s is 27 ticks, which keeps
-- the send times halfway between ticks. Off a sub-level this costs half a second of silence at the start.
local dfpwm = require "cc.audio.dfpwm"

local SAMPLES = 64800 -- per packet: 1.35 s
local PACKET = SAMPLES * 2 -- bytes of 16-bit audio per playAudioEx call (it takes up to 131072)
local CHUNK = SAMPLES / 8 -- bytes of DFPWM per playAudio call (cc-audio-expand's playAudio takes up to 65536 samples)
local LEAD = 25200 -- samples in the silent packet: 0.525 s
local PIECE = 512 -- DFPWM bytes decoded between yields
local RETRY = 10 -- seconds to wait when neither the source nor the fallback opens

-- A file named like sins.24k.dfpwm holds 24000 samples/s (16k works too); it is decoded and stretched back to
-- the speaker's 48 kHz by linear interpolation, so a track takes 1/2 (or 1/3) of the disk.
local function rateFactor(path)
  local k = path:match("%.(%d+)k%.dfpwm$")
  local f = k and 48 / tonumber(k)
  return (f and f >= 1 and f == math.floor(f)) and f or 1
end

local music = { speaker = nil } -- music.speaker: a peripheral name; nil means "find one"
-- ends: os.epoch time the client runs out of audio as the server counts it, nil when nothing is queued. It carries
-- over from one pass of a track to the next, so a loop doesn't need the silent packet again.
local st = { src = nil, fallback = nil, volume = 1, ducked = false, gen = 0, ends = nil }

local function wake() os.queueEvent("music_cmd") end

--- Start (or switch to) a track. It loops until stop().
function music.play(src, opts)
  st.src, st.fallback = src, opts and opts.fallback
  st.gen = st.gen + 1 -- tells the loop to drop what it is reading
  st.ends = nil
  wake()
end

function music.stop()
  st.src = nil
  st.gen = st.gen + 1
  st.ends = nil
  wake()
end

--- 0 to 3 (the speaker's range); takes effect on the next packet.
function music.setVolume(v)
  st.volume = math.max(0, math.min(3, tonumber(v) or 1))
end

--- true: go quiet at once and hold the place; false: carry on.
function music.duck(on)
  st.ducked = on and true or false
  wake()
end

function music.isPlaying() return st.src ~= nil and not st.ducked end

local function getSpeaker()
  if music.speaker then return peripheral.wrap(music.speaker) end
  return peripheral.find("speaker")
end

-- cc.audio.dfpwm's decoder with the predictor inlined and no bit library: same output, about twice as fast.
-- Appends to out from index n + 1 and returns the new length.
local function decoder()
  local charge, strength, prev, lp, prevCharge = 0, 0, 0, 0, 0
  local byte = string.byte
  return function(s, out, n)
    for i = 1, #s do
      local b = byte(s, i)
      for _ = 1, 8 do
        local bit = b % 2
        b = (b - bit) / 2
        local target = bit == 1 and 127 or -128
        local x = strength * (target - charge) + 512
        local nc = charge + (x - x % 1024) / 1024
        if nc == charge and nc ~= target then nc = nc + (bit == 1 and 1 or -1) end
        if bit == prev then
          if strength ~= 1023 then strength = strength + 1 end
        elseif strength ~= 0 then
          strength = strength - 1
        end
        if strength < 8 then strength = 8 end
        local aj = nc
        if bit ~= prev then
          local y = nc + prevCharge + 1
          aj = (y - y % 2) / 2
        end
        prevCharge, prev, charge = nc, bit, nc
        local z = (aj - lp) * 140 + 128
        lp = lp + (z - z % 256) / 256
        n = n + 1
        out[n] = lp
      end
    end
    return n
  end
end
music.decoder = decoder -- for the tests

-- Stretch decoded samples by an integer factor onto the end of out, carrying the last sample into the next piece.
local function upsample(buf, f, prev, out, n)
  for i = 1, #buf do
    local cur = buf[i]
    local step = (cur - prev) / f
    for j = 1, f - 1 do n = n + 1; out[n] = prev + step * j end
    n = n + 1; out[n] = cur
    prev = cur
  end
  return n, prev
end

local function canOgg()
  local sp = getSpeaker()
  return sp and sp.playAudioEx and pcall(require, "cc.audio.ogg")
end

-- list.txt: one "file skip keep" line per part (samples to cut from the front, samples to play)
local function readList(dir)
  local f = fs.open(fs.combine(dir, "list.txt"), "r")
  if not f then return nil end
  local parts = {}
  for line in f.readLine do
    local name, skip, keep = line:match("^(%S+)%s+(%d+)%s+(%d+)")
    if name then parts[#parts + 1] = { file = fs.combine(dir, name), skip = tonumber(skip), keep = tonumber(keep) } end
  end
  f.close()
  return #parts > 0 and { parts = parts } or nil
end

local function open(path)
  if path:match("^https?://") then
    if not http then return nil end
    return http.get(path, nil, true)
  end
  if fs.isDir(path) then return canOgg() and readList(path) or nil end
  return fs.exists(path) and fs.open(path, "rb") or nil
end

-- Wait for a speaker_audio_empty or a command, whichever comes first. The timer is a backstop: the event is lost
-- if it lands while playAudioEx waits for the main thread. 0.5 s still leaves the next packet in time.
local function waitSpace()
  local t = os.startTimer(0.5)
  while true do
    local ev, id = os.pullEvent()
    if ev == "speaker_audio_empty" or ev == "music_cmd" or (ev == "timer" and id == t) then return end
  end
end

local function stopFor(speaker, gen)
  if speaker and st.gen ~= gen then
    speaker.stop()
    st.ends = nil
    sleep(0.1) -- stop() lands on the next tick and drops audio pushed before it; let it land
  end
end

-- Returns send(packet): it blocks until the speaker takes the packet, starting with the silent one (see the top)
-- after a start, a duck or a stall. A duck holds the packet and sends it once the duck is over. Returns false when
-- the settings change.
local function feeder(speaker, gen, push, silence)
  return function(packet)
    while st.gen == gen do
      local now = os.epoch("utc")
      if st.ducked then
        speaker.stop()
        st.ends = nil
        while st.ducked and st.gen == gen do os.pullEvent("music_cmd") end
      elseif not st.ends or now > st.ends - 100 then
        -- fresh start, or we were so late the server will start over: the silent packet sets it up again
        if push(silence) then st.ends = now + LEAD / 48 else waitSpace() end
      elseif push(packet) then
        st.ends = math.max(now, st.ends) + SAMPLES / 48
        return true
      else
        waitSpace()
      end
    end
    return false
  end
end

-- Play an Ogg track folder to its end. Returns early (false) when the settings change.
local function playParts(track, gen)
  local speaker = getSpeaker()
  local ogg = require "cc.audio.ogg"
  local send = feeder(speaker, gen, function(s)
    return speaker.playAudioEx(s, { format = "pcm_s16le", volume = st.volume })
  end, ("\0"):rep(LEAD * 2))
  local rest = "" -- packets run on across parts, so every one is a full 1.35 s
  for _, p in ipairs(track.parts) do
    local f = fs.open(p.file, "rb")
    if not f then error("missing " .. p.file) end
    local data = f.readAll()
    f.close()
    local pcm, info = ogg.decode(data)
    assert(info.sampleRate == 48000 and info.channels == 1, p.file .. " must be mono 48 kHz")
    pcm = rest .. pcm:sub(p.skip * 2 + 1, (p.skip + p.keep) * 2)
    local i = 1
    while #pcm - i + 1 >= PACKET do
      if not send(pcm:sub(i, i + PACKET - 1)) then stopFor(speaker, gen); return false end
      i = i + PACKET
    end
    rest = pcm:sub(i)
  end
  if #rest > 0 and not send(rest .. ("\0"):rep(PACKET - #rest)) then stopFor(speaker, gen); return false end
  return true
end

local silent -- the silent packet as a table, made once

-- Play a DFPWM file or download to its end. Returns early (false) when the settings change.
local function playDfpwm(h, gen, factor)
  local speaker = getSpeaker()
  if not speaker then return false end
  if not silent then
    silent = {}
    for i = 1, LEAD do silent[i] = 0 end
  end
  local send = feeder(speaker, gen, function(buf) return speaker.playAudio(buf, st.volume) end, silent)
  local chunkBytes = CHUNK / factor -- 1.35 s whatever the rate
  local prev = 0
  local dec = decoder()
  while true do
    local chunk = h.read(chunkBytes)
    if not chunk or #chunk == 0 then return true end -- end of the track
    -- a whole chunk at once holds up the cab's 10 Hz position reports, so decode it in pieces and yield between
    local buf, n, worst = {}, 0, 0
    for i = 1, #chunk, PIECE do
      local t0 = os.clock()
      local s = chunk:sub(i, i + PIECE - 1)
      if factor > 1 then
        local part = {}
        dec(s, part, 0)
        n, prev = upsample(part, factor, prev, buf, n)
      else
        n = dec(s, buf, n)
      end
      worst = math.max(worst, os.clock() - t0)
      os.queueEvent("music_yield"); os.pullEvent("music_yield")
    end
    music.lastPiece = worst -- for the tests
    for i = n + 1, SAMPLES do buf[i] = 0 end -- the last chunk, padded so the timing holds
    if not send(buf) then stopFor(speaker, gen); return false end
  end
end

--- The player loop. Never returns; run it inside parallel.waitForAny / waitForAll.
function music.run()
  while true do
    if not st.src then
      os.pullEvent("music_cmd")
    else
      local gen = st.gen
      local path = st.src
      local h = open(path)
      if not h and st.fallback then path = st.fallback; h = open(path) end
      if not h then
        -- nothing to play: wait, but wake early for a new command
        local t = os.startTimer(RETRY)
        repeat
          local ev, id = os.pullEvent()
        until (ev == "timer" and id == t) or (ev == "music_cmd" and st.gen ~= gen)
      else
        local ok, done
        if h.parts then
          ok, done = pcall(playParts, h, gen)
        else
          ok, done = pcall(playDfpwm, h, gen, rateFactor(path))
          h.close()
        end
        -- an error, or no speaker at all (returns false without the settings changing): wait before trying
        -- again. Spinning here once got the cab killed for not yielding, and the car lost its position with it.
        if not ok or (not done and st.gen == gen) then
          local t = os.startTimer(1)
          repeat local ev, id = os.pullEvent() until ev == "timer" and id == t
        end
      end
    end
  end
end

return music
