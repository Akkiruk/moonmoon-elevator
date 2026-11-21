-- Motion profile: accelerate, cruise, slow down, then level at low speed.
-- Speeds are in blocks per second (signed, + is up); the motor gets whole RPM.
local M = {}

function M.toSpeed(p, rpm) return rpm * p.blocksPerRev / 60 end
function M.toRpm(p, v) return v * 60 / p.blocksPerRev end

-- Distance needed to stop from speed v (blocks/s), including the levelling creep.
function M.stopDistance(p, v)
  local vl = M.toSpeed(p, p.levelRpm)
  local fast = math.max(0, math.abs(v) - vl)
  return p.levelZone + fast * fast / (2 * p.decel) + p.stopTol
end

local function round(x) if x >= 0 then return math.floor(x + 0.5) end return -math.floor(-x + 0.5) end

-- One control step towards target height. st.v holds the commanded speed between calls.
-- Returns rpm (signed whole number) and true once arrived (st.v is then 0).
function M.drive(p, st, y, target, dt)
  local e = target - y
  local d = math.abs(e)
  if d <= p.stopTol then st.v = 0; return 0, true end
  local s = e > 0 and 1 or -1
  local vl = M.toSpeed(p, p.levelRpm)
  local vmax = M.toSpeed(p, p.cruiseRpm)
  local want
  if d <= p.levelZone then want = vl
  else want = math.min(vmax, vl + math.sqrt(2 * p.decel * (d - p.levelZone))) end
  local vs = s * want
  local cur = st.v or 0
  -- speeding up (same direction, larger) is limited by accel; anything else by twice the decel
  local up = (cur == 0 or (cur > 0) == (vs > 0)) and math.abs(vs) > math.abs(cur)
  local lim = (up and p.accel or 2 * p.decel) * dt
  if vs > cur + lim then vs = cur + lim elseif vs < cur - lim then vs = cur - lim end
  st.v = vs
  local rpm = round(M.toRpm(p, vs))
  -- never creep slower than levelRpm while still short of the stop, and only towards the target
  if rpm * s < p.levelRpm and (vs == 0 or (vs > 0) == (s > 0)) then rpm = s * p.levelRpm; st.v = M.toSpeed(p, rpm) end
  if rpm > p.maxRpm then rpm = p.maxRpm elseif rpm < -p.maxRpm then rpm = -p.maxRpm end
  return rpm, false
end

return M
