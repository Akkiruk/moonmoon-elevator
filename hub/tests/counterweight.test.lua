-- The decorative counterweight: where it should be and how its motor gets driven.
package.path = "/?.lua;/?/init.lua;" .. package.path
local CW = require "counterweight"

local cfg = {
  counterweightControl = { gain = 16, maxRpm = 96, deadband = 0.3, maxAge = 1 },
  cars = { A = { counterweight = { motor = "m", motorSign = 1, top = 128, bottom = 69 } }, B = {} },
}
local stops = { 69, 75, 89, 128 }

ccunit.test("mirrors the car: top when the car is at the bottom, and the other way round", function()
  local cw = cfg.cars.A.counterweight
  ccunit.eq(CW.target(cw, 69, 128, 69), 128)
  ccunit.eq(CW.target(cw, 69, 128, 128), 69)
  ccunit.eq(CW.target(cw, 69, 128, 98.5), 98.5)
  ccunit.eq(CW.target(cw, 69, 128, 60), 128, "clamped below the bottom stop")
end)

ccunit.test("drives towards the target, capped, and rests inside the deadband", function()
  local now = 10
  local car = { y = 69, t = now }
  ccunit.eq(CW.step(cfg, "A", stops, car, { y = 100, t = now }, now), 96, "far below: full speed up")
  ccunit.eq(CW.step(cfg, "A", stops, car, { y = 127, t = now }, now), 16)
  ccunit.eq(CW.step(cfg, "A", stops, car, { y = 127.8, t = now }, now), 0, "close enough")
  ccunit.eq(CW.step(cfg, "A", stops, car, { y = 128.35, t = now }, now), -6, "small error still moves it")
end)

ccunit.test("stops when a position is missing or old, and does nothing without a counterweight", function()
  local now = 10
  ccunit.eq(CW.step(cfg, "A", stops, nil, { y = 100, t = now }, now), 0)
  ccunit.eq(CW.step(cfg, "A", stops, { y = 69, t = now }, nil, now), 0)
  ccunit.eq(CW.step(cfg, "A", stops, { y = 69, t = now }, { y = 100, t = now - 2 }, now), 0, "stale")
  ccunit.eq(CW.step(cfg, "B", stops, { y = 69, t = now }, { y = 100, t = now }, now), nil)
end)

ccunit.test("motorSign flips the direction", function()
  local c2 = { counterweightControl = cfg.counterweightControl,
    cars = { A = { counterweight = { motor = "m", motorSign = -1, top = 128, bottom = 69 } } } }
  ccunit.eq(CW.step(c2, "A", stops, { y = 69, t = 0 }, { y = 100, t = 0 }, 0), -96)
end)
