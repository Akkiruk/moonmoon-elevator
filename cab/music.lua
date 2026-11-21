-- Looping DFPWM player for the cab speaker.
--
--   local music = require "music"
--   music.play("https://.../sins.dfpwm", { fallback = "/tracks/sins-short.dfpwm" })
--   parallel.waitForAny(music.run, display, rednetLoop)
--
-- music.run() is the player loop: run it beside your other code, it only reacts to events.
-- The other functions just change settings and wake it, so call them from anywhere.
-- Memory use is one chunk (CHUNK bytes), whatever the length of the track.
local dfpwm = require "cc.audio.dfpwm"

local CHUNK = 4096 -- bytes of DFPWM per playAudio call = 32768 samples = 0.68 s
local RETRY = 10 -- seconds to wait when neither the source nor the fallback opens

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
local function playOne(h, gen)
  local dec = dfpwm.make_decoder()
  local speaker = getSpeaker()
  while h and st.gen == gen and speaker do
    if st.ducked then
      speaker.stop()
      dec = dfpwm.make_decoder() -- do not carry the decoder's state over the gap
      while st.ducked and st.gen == gen do os.pullEvent("music_cmd") end
    else
      local chunk = h.read(CHUNK)
      if not chunk or #chunk == 0 then return true end -- end of the track
      local buf = dec(chunk)
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
      local h = open(st.src) or (st.fallback and open(st.fallback))
      if not h then
        -- nothing to play: wait, but wake early for a new command
        local t = os.startTimer(RETRY)
        repeat
          local ev, id = os.pullEvent()
        until (ev == "timer" and id == t) or (ev == "music_cmd" and st.gen ~= gen)
      else
        local ok, err = pcall(playOne, h, gen)
        h.close()
        if not ok then
          -- e.g. the speaker was broken or removed: do not spin, and keep the player alive
          local t = os.startTimer(1)
          repeat local ev, id = os.pullEvent() until ev == "timer" and id == t
        end
      end
    end
  end
end

return music
