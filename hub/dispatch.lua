-- Dispatch: which car answers a hall call, and where each car goes next (collective control: serve the stops in
-- the direction of travel, then reverse).
local motion = require "motion"
local D = {}

-- Does car c have a stop at floor i (a car call, or a hall call assigned to it)?
local function wantsUp(ctl, c, i) return c.calls[i] or ctl.hall.up[i] == c.name end
local function wantsDown(ctl, c, i) return c.calls[i] or ctl.hall.down[i] == c.name end
local function wants(ctl, c, i) return wantsUp(ctl, c, i) or wantsDown(ctl, c, i) end
D.wants = wants

function D.anyStops(ctl, c)
  for i = 1, ctl.n do if wants(ctl, c, i) then return true end end
  return false
end

-- Floors beyond f in direction d with a stop for c.
function D.stopsBeyond(ctl, c, f, d)
  if d == "up" then for i = f + 1, ctl.n do if wants(ctl, c, i) then return true end end
  else for i = f - 1, 1, -1 do if wants(ctl, c, i) then return true end end end
  return false
end

-- How far ahead (blocks) a moving car must look before a floor counts as reachable.
local function margin(ctl, c)
  if not c.moving then return ctl.cfg.motion.levelTol end
  return motion.stopDistance(ctl.cfg.motion, c.vcmd or 0)
end

-- Next stop for car c: floor index and the direction it travels in to get there.
-- Returns nil when it has no stops. A stationary car level at a floor that has a stop there returns that floor.
function D.nextTarget(ctl, c)
  if not c.y or not D.anyStops(ctl, c) then return nil end
  local y, st = c.y, c.stops
  local m = margin(ctl, c)
  local function above(i) return st[i] > y + m end
  local function below(i) return st[i] < y - m end
  local d = c.dir
  if c.moving and c.vcmd and c.vcmd ~= 0 then d = c.vcmd > 0 and "up" or "down" end
  if not c.moving and c.atFloor and wants(ctl, c, c.atFloor) then
    -- a call at the floor it stands at: serve it here when it fits the direction (or there is nothing else)
    local f = c.atFloor
    if d == nil or (d == "up" and wantsUp(ctl, c, f)) or (d == "down" and wantsDown(ctl, c, f))
      or not D.stopsBeyond(ctl, c, f, d) then
      return f, d
    end
  end
  if d == nil then
    local best, bd
    for i = 1, ctl.n do
      if wants(ctl, c, i) and (not c.atFloor or i ~= c.atFloor) then
        local dist = math.abs(st[i] - y)
        if not bd or dist < bd then best, bd = i, dist end
      end
    end
    if not best then return nil end
    d = st[best] > y and "up" or "down"
  end
  for _ = 1, 2 do
    if d == "up" then
      for i = 1, ctl.n do if above(i) and wantsUp(ctl, c, i) then return i, "up" end end
      for i = ctl.n, 1, -1 do if above(i) and ctl.hall.down[i] == c.name then return i, "up" end end
      d = "down"
    else
      for i = ctl.n, 1, -1 do if below(i) and wantsDown(ctl, c, i) then return i, "down" end end
      for i = 1, ctl.n do if below(i) and ctl.hall.up[i] == c.name then return i, "down" end end
      d = "up"
    end
  end
  -- every stop is behind a moving car's stopping distance: it carries on to the nearest floor it can stop at
  return nil
end

-- Cost (blocks of travel, roughly) for car c to answer a hall call at floor f going d. nil = cannot.
function D.cost(ctl, c, f, d)
  if not ctl:available(c) then return nil end
  local y, fy = c.y, c.stops[f]
  local dir = c.dir
  if c.moving and c.vcmd and c.vcmd ~= 0 then dir = c.vcmd > 0 and "up" or "down" end
  local busy = D.anyStops(ctl, c)
  if not busy and not c.moving then return math.abs(fy - y) end
  dir = dir or (fy >= y and "up" or "down")
  local m = margin(ctl, c)
  if dir == "up" then
    if fy > y + m - 0.001 and d == "up" then return fy - y end
    local top = y
    for i = 1, ctl.n do if wants(ctl, c, i) and c.stops[i] > top then top = c.stops[i] end end
    if fy > top then top = fy end
    return (top - y) + math.abs(top - fy) + 1
  else
    if fy < y - m + 0.001 and d == "down" then return y - fy end
    local bot = y
    for i = 1, ctl.n do if wants(ctl, c, i) and c.stops[i] < bot then bot = c.stops[i] end end
    if fy < bot then bot = fy end
    return (y - bot) + math.abs(bot - fy) + 1
  end
end

-- Give every unassigned hall call (or one whose car can no longer serve it) to the cheapest car.
function D.assign(ctl)
  for _, d in ipairs({ "up", "down" }) do
    local calls = ctl.hall[d]
    for i = 1, ctl.n do
      local who = calls[i]
      if who ~= nil and (who == false or not ctl:available(ctl.cars[who])) then
        local best, bc
        for _, name in ipairs(ctl.order) do
          local cost = D.cost(ctl, ctl.cars[name], i, d)
          if cost and (not bc or cost < bc - 1e-6) then best, bc = name, cost end
        end
        calls[i] = best or false
      end
    end
  end
end

return D
