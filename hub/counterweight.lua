-- The counterweight is decorative: it hangs on its own winch with its own motor and gets steered to mirror the car.
-- Nothing here is a safety check. When anything is missing (its position, the car's, the motor) the motor stops.
local M = {}

-- Where it should hang for a car at height y: a straight line from `top` (car at the bottom stop) to `bottom`
-- (car at the top stop).
function M.target(cw, carLow, carHigh, y)
  local f = (y - carLow) / (carHigh - carLow)
  f = math.max(0, math.min(1, f))
  return cw.top + (cw.bottom - cw.top) * f
end

-- Motor rpm to close the gap, whole numbers, + moves it up before motorSign.
function M.rpm(ctl, target, y)
  local e = target - y
  if math.abs(e) <= ctl.deadband then return 0 end
  local r = math.max(-ctl.maxRpm, math.min(ctl.maxRpm, e * ctl.gain))
  r = r >= 0 and math.floor(r + 0.5) or -math.floor(-r + 0.5)
  if r == 0 then r = e > 0 and 1 or -1 end
  return r
end

-- One control step for car `name`. pos = the car's { y, t }, cwPos = the counterweight's { y, t }.
function M.step(cfg, name, stops, pos, cwPos, now)
  local cw = cfg.cars[name].counterweight
  if not cw then return nil end
  local ctl = cfg.counterweightControl
  if not (pos and cwPos and now - pos.t <= ctl.maxAge and now - cwPos.t <= ctl.maxAge) then return 0 end
  local tgt = M.target(cw, stops[1], stops[#stops], pos.y)
  return M.rpm(ctl, tgt, cwPos.y) * (cw.motorSign or 1)
end

return M
