-- Run from this folder: craftos-mcp test --world cab.world.json
-- The test feeds the player small files it writes itself (CHUNK = 4096 bytes), and spies on the speaker.
-- http is not tested: the emulator has no network, so URL sources are untested here.
local music = require "music"

local realFind = peripheral.find
local calls, stops, volumes
local function spy()
  calls, stops, volumes = 0, 0, {}
  local sp = realFind("speaker")
  local fake = setmetatable({
    playAudio = function(buf, vol)
      local ok = sp.playAudio(buf, vol)
      if ok then calls = calls + 1; volumes[#volumes + 1] = vol end
      return ok
    end,
    stop = function() stops = stops + 1; return sp.stop() end,
  }, { __index = sp })
  peripheral.find = function(t) if t == "speaker" then return fake end return realFind(t) end
end

local function write(path, chunks)
  local f = fs.open(path, "wb")
  for _ = 1, chunks do f.write(string.rep("\x55\xAA", 2048)) end
  f.close()
end

-- run music.run beside a scenario; return when the scenario returns
local function with(scenario)
  parallel.waitForAny(music.run, function() scenario() end)
end

ccunit.test("feeds the whole file, then loops", function()
  spy()
  write("/t3.dfpwm", 3)
  music.setVolume(1)
  with(function()
    music.play("/t3.dfpwm")
    sleep(5) -- each chunk is 0.68 s of audio: 3 chunks per pass, so more than 3 calls means it looped
  end)
  ccunit.truthy(calls > 3, "looped, calls=" .. calls)
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
  ccunit.truthy(calls >= 3, "kept feeding, calls=" .. calls)
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
