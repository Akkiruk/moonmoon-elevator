-- Looping DFPWM player for the cab speaker.
--
--   local music = require "music"
--   music.play("/tracks/sins.dfpwm")   -- or an http URL; { fallback = path } is optional
--   parallel.waitForAny(music.run, display, rednetLoop)
--
-- music.run() is the player loop: run it beside your other code, it only reacts to events.
-- The other functions just change settings and wake it, so call them from anywhere.
-- Memory use is one chunk (CHUNK bytes), whatever the length of the track.
local dfpwm = require "cc.audio.dfpwm"

local CHUNK = 4096 -- bytes of DFPWM per playAudio call = 32768 samples = 0.68 s
local PIECE = 256  -- bytes decoded between yields
local RETRY = 10 -- seconds to wait when neither the source nor the fallback opens

-- A file named like sins.24k.dfpwm holds 24000 samples/s (16k works too); it is decoded and stretched back to
-- the speaker's 48 kHz by linear interpolation, so a track takes 1/2 (or 1/3) of the disk.
local function rateFactor(path)
  local k = path:match("%.(%d+)k%.dfpwm$")
  local f = k and 48 / tonumber(k)
  return (f and f >= 1 and f == math.floor(f)) and f or 1
end

local music = { speaker = nil } -- music.speaker: a peripheral name; nil means "find one"
local st = { src = nil, fallback = nil, volume = 1, ducked = false, gen = 0 }

local function wake() os.queueEvent("music_cmd") end

--- Start (or switch to) a track. src is a /path or an http(s) URL; it loops until stop().
function music.play(src, opts)
  st.src, st.fallback = src, opts and opts.fallback
  st.gen = st.gen + 1 -- tells the loop to drop what it is reading
  wake()
end

function music.stop()
  st.src = nil
  st.gen = st.gen + 1
  wake()
end

--- 0 to 3 (the speaker's range); takes effect on the next chunk.
function music.setVolume(v)
  st.volume = math.max(0, math.min(3, tonumber(v) or 1))
end

--- true: go quiet at once and hold the place; false: carry on.
function music.duck(on)
  st.ducked = on and true or false
  wake()
end

function music.isPlaying() return st.src ~= nil and not st.ducked end

-- Stretch decoded samples (-128..127) by an integer factor, carrying the last sample into the next chunk.
local function upsample(buf, f, prev)
  local out, n = {}, 0
  for i = 1, #buf do
    local cur = buf[i]
    local step = (cur - prev) / f
    for j = 1, f - 1 do n = n + 1; out[n] = prev + step * j end
    n = n + 1; out[n] = cur
    prev = cur
  end
  return out, prev
end

local function getSpeaker()
  if music.speaker then return peripheral.wrap(music.speaker) end
  return peripheral.find("speaker")
end

local function open(path)
  if path:match("^https?://") then
    if not http then return nil end
    local h = http.get(path, nil, true)
    return h
  end
  return fs.exists(path) and fs.open(path, "rb") or nil
end

-- Wait for a speaker_audio_empty or a command, whichever comes first.
local function waitSpace()
  while true do
    local ev = os.pullEvent()
    if ev == "speaker_audio_empty" or ev == "music_cmd" then return end
  end
end

-- Play one source to its end. Returns early when the settings change (gen) .
local function playOne(h, gen, factor)
  local chunkBytes = math.floor(CHUNK / factor) -- keeps the output at 32768 samples
  local prev = 0
  local dec = dfpwm.make_decoder()
  local speaker = getSpeaker()
  while h and st.gen == gen and speaker do
    if st.ducked then
      speaker.stop()
      dec, prev = dfpwm.make_decoder(), 0 -- do not carry the decoder's state over the gap
      while st.ducked and st.gen == gen do os.pullEvent("music_cmd") end
    else
      local chunk = h.read(chunkBytes)
      if not chunk or #chunk == 0 then return true end -- end of the track
      -- a whole chunk took 0.4-0.5 s of CPU on the test server, long enough to hold up the cab's 10 Hz position
      -- reports and trip the hub's lost-position check; small pieces with a yield in between keep it fair
      local buf, n, worst = {}, 0, 0
      for i = 1, #chunk, PIECE do
        local t0 = os.clock()
        local part = dec(chunk:sub(i, i + PIECE - 1))
        if factor > 1 then part, prev = upsample(part, factor, prev) end
        for j = 1, #part do n = n + 1; buf[n] = part[j] end
        worst = math.max(worst, os.clock() - t0)
        os.queueEvent("music_yield"); os.pullEvent("music_yield")
      end
      music.lastUpsample = worst -- seconds of CPU for the slowest piece, for the tests
      while st.gen == gen and not st.ducked and not speaker.playAudio(buf, st.volume) do
        waitSpace()
      end
      -- if we left the loop because of a duck, this chunk is dropped: the track resumes just after it
    end
  end
  if speaker and st.gen ~= gen then
    speaker.stop()
    sleep(0.1) -- stop() lands on the next tick and drops audio pushed before it; let it land
  end
  return false
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
        local ok, done = pcall(playOne, h, gen, rateFactor(path))
        h.close()
        -- an error, or no speaker at all (playOne returns false without the settings changing): wait before trying
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
