-- hw.lua with fake peripherals: the bottom rope motor follows the car's motor, mirrored, plus a steady reel-in.
package.path = "/?.lua;/?/init.lua;" .. package.path
local HW = require "hw"

local function rig(tension)
  local speeds, out = {}, {}
  local function motor(n) return { setGeneratedSpeed = function(r) speeds[n] = r end } end
  local relay = { setOutput = function(side, v) out[side] = v end, getInput = function() return false end }
  local per = {
    isPresent = function(n) return n == "car" or n == "bottom" or n == "relay" end,
    wrap = function(n) if n == "relay" then return relay end return motor(n) end,
  }
  local cfg = {
    carOrder = { "A" }, floors = { "1", "2" },
    cars = { A = { motor = "car", motorSign = -1, brakeRelease = { "relay", "left" }, landingDoors = {},
      tension = tension } },
  }
  return HW.new(cfg, per), speeds
end

local function write(hw, release, rpm)
  hw:write({ cars = { A = { release = release, rpm = rpm, doorOpen = false, landing = {} } } }, 0)
end

ccunit.test("bottom rope pays out while the car climbs and reels in while it comes down", function()
  local hw, speeds = rig({ motor = "bottom", motorSign = 1, reelRpm = 4 })
  write(hw, true, 64)
  ccunit.eq(speeds.car, -64, "car motor honours its own sign")
  ccunit.eq(speeds.bottom, 60, "64 out, less 4 of steady reel-in")
  write(hw, true, -64)
  ccunit.eq(speeds.bottom, -68)
end)

ccunit.test("braked: the bottom rope just keeps itself taut", function()
  local hw, speeds = rig({ motor = "bottom", motorSign = -1, reelRpm = 4 })
  write(hw, false, 64) -- rpm without release counts as stopped
  ccunit.eq(speeds.car, 0)
  ccunit.eq(speeds.bottom, 4, "motorSign -1 flips it")
end)

ccunit.test("safeStop stops the bottom rope motor too; no tension config, no motor", function()
  local hw, speeds = rig({ motor = "bottom", motorSign = 1, reelRpm = 4 })
  write(hw, true, 64)
  hw:safeStop()
  ccunit.eq(speeds.bottom, 0)
  local hw2, speeds2 = rig(nil)
  write(hw2, true, 64)
  ccunit.eq(speeds2.bottom, nil)
end)
