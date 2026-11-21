-- The hub's controller as a pure state machine: step(now, inputs) -> outputs. No peripherals, no sleeping, so it can
-- be driven by the simulated shaft in the tests exactly as by hub.lua in the world.
--
-- inputs = {
--   fire, lockdown, fireReset = bool,
--   hallUp = { [floor] = bool }, hallDown = { [floor] = bool },
--   cars = { A = {
--     y, yTime,                      -- last GPS height and when it arrived (hub clock); y = nil: no position
--     contacts = { [floor] = bool }, contactsWired = { [floor] = bool },
--     door = { open, ok, t },        -- last door_state from the cab and when it arrived
--     inspect, inspectUp, inspectDown, firefighter = bool,
--     blocked = bool,                -- a player stands in the doorway of the floor the car is at
--   } },
--   events = { { type = "call", car, floor } | { type = "door", car, cmd } | { type = "alarm_button", car }
--            | { type = "keycard", car } | { type = "reset", car } },
-- }
-- outputs = {
--   cars = { A = { rpm, release, doorOpen, landing = { [floor] = bool } } },
--   hallUpLit, hallDownLit = { [floor] = bool },
--   messages = { protocol messages to send to the cabs (chime, alarm, music) },
-- }
local motion = require "motion"
local dispatch = require "dispatch"

local E = {}
E.__index = E

local function set(list, index)
  local s = {}
  for _, n in ipairs(list or {}) do if index[n] then s[index[n]] = true end end
  return s
end

function E.new(cfg)
  local self = setmetatable({}, E)
  self.cfg = cfg
  self.floors = cfg.floors
  self.n = #cfg.floors
  self.index = {}
  for i, n in ipairs(cfg.floors) do self.index[n] = i end
  self.recall = self.index[cfg.recallFloor or "G"]
  self.keycardFloors = set(cfg.keycardFloors, self.index)
  self.lab = set(cfg.labFloors, self.index)
  self.boundary = self.index[cfg.lockdownBoundary or "P3"]
  self.hall = { up = {}, down = {} } -- [floor] = car name, false (waiting for a car) or nil
  self.fireLatched = false
  self.lockdown = false
  self.order = cfg.carOrder or { "A", "B" }
  self.cars = {}
  self.now = nil
  self.prev = { hallUp = {}, hallDown = {} }
  self.messages = {}
  for _, name in ipairs(self.order) do
    local cc = cfg.cars and cfg.cars[name] or {}
    local stops = {}
    for i, t in ipairs(cc.thresholds or cfg.thresholds) do stops[i] = t + (cfg.levelOffset or 3) end
    self.cars[name] = {
      name = name, stops = stops, calls = {},
      samples = {}, cmdHist = {},
      dir = nil, lantern = nil, target = nil,
      moving = false, release = false, rpm = 0, vcmd = 0, mot = { v = 0 },
      door = { state = "closing", since = 0, strikes = 0, presses = 0, dwellUntil = 0 },
      keycardUntil = -1, alarmUntil = -1, alarmOn = false,
      zone = {}, msg = nil, msgUntil = -1,
      music = nil, duckUntil = nil,
    }
  end
  return self
end

------------------------------------------------------------------------ helpers

function E:floorIndex(f)
  if type(f) == "number" then return (f >= 1 and f <= self.n) and math.floor(f) or nil end
  return self.index[tostring(f)]
end

function E:send(msg) self.messages[#self.messages + 1] = msg end

local function nearest(c)
  if not c.y then return nil end
  local best, bd
  for i, s in ipairs(c.stops) do
    local d = math.abs(c.y - s)
    if not bd or d < bd then best, bd = i, d end
  end
  return best, bd
end

-- Can this car take hall calls?
function E:available(c)
  return c.mode == "normal" and c.posFresh and not c.fault
end

function E:allowed(i)
  return not (self.lockdown and self.lab[i])
end

local function flash(self, c, text)
  c.msg, c.msgUntil = text, self.now + self.cfg.timing.messageSeconds
end

local function latch(self, c, reason)
  if c.latched then return end
  c.latched = reason
  c.calls = {}
  c.target = nil
end
E.latch = latch

------------------------------------------------------------------------ inputs

local function trimHistory(list, before)
  while #list > 0 and list[1].t < before do table.remove(list, 1) end
end

function E:updatePosition(c, ci)
  local now, sf = self.now, self.cfg.safety
  if ci.y and ci.yTime and ci.yTime ~= c.yTime then
    c.y, c.yTime = ci.y, ci.yTime
    c.samples[#c.samples + 1] = { t = ci.yTime, y = ci.y }
    trimHistory(c.samples, ci.yTime - 2)
    c.vMeas = nil
    for k = #c.samples - 1, 1, -1 do
      local s = c.samples[k]
      if ci.yTime - s.t >= sf.speedWindow then
        c.vMeas = (ci.y - s.y) / (ci.yTime - s.t)
        break
      end
    end
  elseif not ci.y then
    c.yLost = true
  end
  c.posFresh = ci.y ~= nil and c.yTime ~= nil and (now - c.yTime) <= self.cfg.timing.posMaxAge
  if not ci.y then c.posFresh = false end
  if c.posFresh then c.yLost = false end
  -- where is it?
  local f, d = nearest(c)
  c.nearest = f
  c.atFloor = (f and not c.moving and d <= self.cfg.motion.levelTol and c.posFresh) and f or nil
end

function E:updateDoorReading(c, ci)
  local t, d = self.cfg.timing, ci.door
  local known = d ~= nil and d.ok and d.t ~= nil and (self.now - d.t) <= t.doorStateMaxAge
  c.doorKnown = known and true or false
  c.doorReadOpen = known and d.open and true or false
  c.doorReadClosed = known and not d.open or false
  if known then c.unknownSince = nil
  elseif not c.unknownSince then c.unknownSince = self.now end
end

------------------------------------------------------------------------ safety

function E:safety(c, ci)
  local now, sf, p = self.now, self.cfg.safety, self.cfg.motion
  if c.latched then return end
  if c.moving and not c.posFresh then return latch(self, c, "Lost position") end
  if not c.posFresh then return end
  -- speed governor and cable failure, from GPS against what was commanded
  if c.vMeas and c.yTime and now - c.yTime <= self.cfg.timing.posMaxAge then
    local lo, hi = 0, 0
    for _, h in ipairs(c.cmdHist) do
      if h.v < lo then lo = h.v end
      if h.v > hi then hi = h.v end
    end
    local gov = motion.toSpeed(p, p.cruiseRpm) * sf.governorFactor
    if c.vMeas < lo - sf.speedMargin then return latch(self, c, "Cable failure") end
    if math.abs(c.vMeas) > gov or c.vMeas > hi + sf.speedMargin then return latch(self, c, "Overspeed") end
  end
  -- floor contacts against GPS
  local contacts, wired = ci.contacts or {}, ci.contactsWired
  for i, s in ipairs(c.stops) do
    if not wired or wired[i] then
      local d = math.abs(c.y - s)
      local lit = contacts[i] and true or false
      if lit and d > sf.contactFar then
        return latch(self, c, "Contact " .. self.floors[i] .. " lit away from car")
      end
      if d <= sf.contactWindow then
        local z = c.zone[i]
        if not z then z = { seen = false, minD = d }; c.zone[i] = z end
        if lit then z.seen = true end
        if d < z.minD then z.minD = d end
      elseif c.zone[i] then
        local z = c.zone[i]
        c.zone[i] = nil
        if not z.seen and z.minD <= sf.contactMustLight then
          return latch(self, c, "Contact " .. self.floors[i] .. " missed")
        end
      end
    end
  end
end

------------------------------------------------------------------------ events

function E:carCall(c, i)
  if not i then return end
  local mode = c.mode
  if mode ~= "normal" and mode ~= "firefighter" then return end
  if not self:allowed(i) then flash(self, c, "Floor unavailable"); return end
  if self.keycardFloors[i] and self.now > c.keycardUntil then flash(self, c, "Swipe keycard first"); return end
  if mode == "normal" and c.atFloor == i and not c.moving then
    c.openReq = true -- its own floor: open the doors
    return
  end
  if c.atFloor == i and not c.moving then return end
  c.calls[i] = true
  local t = self.cfg.timing
  if t.carCallDwell and c.door.state == "open" and c.door.dwellUntil > self.now + t.carCallDwell then
    c.door.dwellUntil = self.now + t.carCallDwell
  end
end

function E:handleEvent(ev)
  if type(ev) ~= "table" then return end
  if ev.type == "reset" and ev.car == nil then
    for _, n in ipairs(self.order) do self:handleEvent({ type = "reset", car = n }) end
    return
  end
  local c = self.cars[ev.car]
  if not c then return end
  local t = self.cfg.timing
  if ev.type == "call" then
    self:carCall(c, self:floorIndex(ev.floor))
  elseif ev.type == "door" then
    if ev.cmd == "open" then c.openPress = true elseif ev.cmd == "close" then c.closePress = true end
  elseif ev.type == "alarm_button" then
    c.alarmUntil = math.max(c.alarmUntil, self.now + t.alarmButtonSeconds)
  elseif ev.type == "keycard" then
    if not self.lockdown then c.keycardUntil = self.now + t.keycardWindow end
  elseif ev.type == "reset" then
    if c.latched then
      c.latched = nil
      c.samples, c.cmdHist, c.zone, c.vMeas = {}, {}, {}, nil
    end
  end
end

function E:hallCall(i, d)
  if not self:allowed(i) or self.fireLatched then return end
  if (d == "up" and i >= self.n) or (d == "down" and i <= 1) then return end
  -- a car standing at the floor answers at once: doors reopen, or their minute restarts
  for _, name in ipairs(self.order) do
    local c = self.cars[name]
    if c.mode == "normal" and not c.fault and c.atFloor == i and not c.moving
      and (c.lantern == nil or c.lantern == d)
      and (c.door.state ~= "closed" or not dispatch.anyStops(self, c)) then
      if c.door.state == "closed" then self:chime(c, (i == 1 and 1) or (i == self.n and 2) or (d == "down" and 2 or 1)) end
      c.openReq, c.lantern = true, d
      return
    end
  end
  if self.hall[d][i] == nil then self.hall[d][i] = false end
end

------------------------------------------------------------------------ fire and lockdown

function E:groupInputs(inp)
  -- fire Phase I: recall on the first signal, stay out of service until the alarm clears and the key is turned
  if inp.fire and not self.fireLatched then
    self.fireLatched = true
    self.hall = { up = {}, down = {} }
    for _, n in ipairs(self.order) do
      local c = self.cars[n]
      c.calls = {}
      if c.fire ~= "firefighter" then c.fire = "recall" end
    end
  end
  self.fireAlarm = inp.fire and true or false
  if inp.fireReset and not self.prevReset and not inp.fire and self.fireLatched then
    self.fireLatched = false
    for _, n in ipairs(self.order) do
      local c = self.cars[n]
      if c.fire ~= "firefighter" then c.fire = nil end
    end
  end
  self.prevReset = inp.fireReset and true or false
  -- lab lockdown
  if inp.lockdown and not self.lockdown then
    self.lockdown = true
    for i in pairs(self.lab) do self.hall.up[i], self.hall.down[i] = nil, nil end
    for _, n in ipairs(self.order) do
      local c = self.cars[n]
      for i in pairs(self.lab) do c.calls[i] = nil end
      c.keycardUntil = -1
      if c.y and not c.latched then
        local f, d = nearest(c)
        if not c.moving and self.lab[f] and d <= self.cfg.motion.levelTol then
          c.lock = "trapped"
        elseif c.y < c.stops[self.boundary] - self.cfg.motion.levelTol then
          c.lock = "stopped"
          c.calls, c.target = {}, nil
          for _, dd in ipairs({ "up", "down" }) do
            for i, who in pairs(self.hall[dd]) do if who == c.name then self.hall[dd][i] = false end end
          end
        end
      end
    end
  elseif not inp.lockdown and self.lockdown then
    self.lockdown = false
    for _, n in ipairs(self.order) do self.cars[n].lock = nil end
  end
end

------------------------------------------------------------------------ mode

function E:modeOf(c, ci)
  if c.latched then return "emergency" end
  if ci.inspect then return "inspection" end
  if c.lock == "trapped" then return "lockdown_trapped" end
  if c.lock == "stopped" then return "out_of_order" end
  if c.fire == "firefighter" then return "firefighter" end
  if c.fire == "recall" then return "fire_recall" end
  if c.fire == "hold" then return "fire_hold" end
  if c.fault then return "out_of_order" end
  return "normal"
end

function E:faultOf(c)
  local t = self.cfg.timing
  if not c.posFresh then return c.y and "No position" or "Waiting for position" end
  if c.unknownSince and self.now - c.unknownSince >= t.doorFaultAfter then return "Door sensor fault" end
  if c.doorStuck then return "Door will not open" end
  return nil
end

------------------------------------------------------------------------ doors

local function doorTo(self, c, state)
  local d = c.door
  if d.state ~= state then d.state, d.since = state, self.now end
end

local function strike(self, c)
  local d, t = c.door, self.cfg.timing
  d.strikes = d.strikes + 1
  if d.strikes >= t.strikes then
    c.alarmUntil = math.max(c.alarmUntil, self.now + t.alarmSeconds)
    flash(self, c, "Please stand clear of the doors")
  end
  d.dwellUntil = self.now + t.reopenDwell
  doorTo(self, c, "opening")
end

-- policy: "auto" (normal service), "close" (close and keep closed), "hold" (open and keep open),
-- "manual" (open and close only on the buttons: firefighter and inspection)
function E:doorStep(c, ci, policy)
  local d, t = c.door, self.cfg.timing
  local now = self.now
  local canOpen = c.atFloor ~= nil and not c.moving
  local openReq = c.openReq
  local openPress, closePress = c.openPress, c.closePress
  c.openReq, c.openPress, c.closePress = nil, nil, nil

  if openPress and policy == "auto" and canOpen then
    d.presses = d.presses + 1
    if d.presses >= t.strikes and d.presses % t.strikes == 0 then
      c.alarmUntil = math.max(c.alarmUntil, now + t.alarmSeconds)
    end
  end

  local st = d.state
  if policy == "hold" then
    if canOpen and st ~= "open" and st ~= "opening" then doorTo(self, c, "opening") end
  elseif policy == "close" then
    if st == "open" or st == "opening" then
      if not ci.blocked then doorTo(self, c, "closing") end
    end
  elseif policy == "manual" then
    if openPress and canOpen and (st == "closed" or st == "closing") then doorTo(self, c, "opening") end
    if closePress and (st == "open" or st == "opening") and not ci.blocked then doorTo(self, c, "closing") end
  else -- auto
    if (openReq or openPress) and canOpen then
      if st == "closed" or st == "closing" then
        d.dwellUntil = now + t.doorDwell
        doorTo(self, c, "opening")
      else
        d.dwellUntil = math.max(d.dwellUntil, now + t.doorDwell)
      end
    end
    if closePress and st == "open" and not ci.blocked then doorTo(self, c, "closing") end
  end

  st = d.state
  if st == "opening" then
    if c.doorReadOpen then
      c.doorStuck = nil
      if now - d.since >= t.doorTravel then
        doorTo(self, c, "open")
        if d.dwellUntil < now then d.dwellUntil = now + t.doorDwell end
      end
    elseif now - d.since >= t.doorTimeout then
      c.doorStuck = true
    end
  elseif st == "open" then
    if policy == "auto" and now >= d.dwellUntil and not ci.blocked then doorTo(self, c, "closing") end
    if policy == "close" and not ci.blocked then doorTo(self, c, "closing") end
  elseif st == "closing" then
    if ci.blocked and canOpen and policy ~= "hold" then
      strike(self, c)
    elseif c.doorReadClosed then
      if not d.closedAt then d.closedAt = now end
      if now - d.closedAt >= t.doorTravel then
        d.closedAt = nil
        d.strikes, d.presses = 0, 0
        doorTo(self, c, "closed")
      end
    elseif now - d.since >= t.doorTimeout then
      if canOpen then strike(self, c) else d.since = now end
    end
    if d.state ~= "closing" then d.closedAt = nil end
  elseif st == "closed" then
    -- a closed door that reads open: someone forced it, or the sensor lies. Close it again (and do not move).
    if c.doorReadOpen then doorTo(self, c, "closing") end
  end
end

local function doorsShut(c)
  return c.door.state == "closed" and c.doorReadClosed
end

------------------------------------------------------------------------ motion

local function hold(self, c)
  c.rpm, c.release, c.moving, c.vcmd = 0, false, false, 0
  c.mot.v = 0
end

-- Drive towards floor i. Returns true on arrival.
function E:driveTo(c, i, dt)
  if not doorsShut(c) or not c.posFresh then hold(self, c); return false end
  local now, p = self.now, self.cfg.motion
  if not c.release then c.release, c.releaseAt, c.moving = true, now, true end
  if now - c.releaseAt < self.cfg.timing.brakeLift then c.rpm = 0; return false end
  local age = math.min(0.3, math.max(0, now - (c.yTime or now)))
  local yEst = c.y + (c.vcmd or 0) * age
  local rpm, arrived = motion.drive(p, c.mot, yEst, c.stops[i], dt)
  if arrived then
    hold(self, c)
    c.atFloor = i
    return true
  end
  c.rpm = rpm
  c.vcmd = motion.toSpeed(p, rpm)
  return false
end

function E:manualMove(c, sign)
  local p = self.cfg.motion
  if sign == 0 or not doorsShut(c) or not c.posFresh then hold(self, c); return end
  if (sign > 0 and c.y >= c.stops[self.n]) or (sign < 0 and c.y <= c.stops[1]) then hold(self, c); return end
  if not c.release then c.release, c.releaseAt, c.moving = true, self.now, true end
  if self.now - c.releaseAt < self.cfg.timing.brakeLift then c.rpm = 0; return end
  c.rpm = sign * p.inspectRpm
  c.vcmd = motion.toSpeed(p, c.rpm)
  c.mot.v = c.vcmd
end

-- The nearest floor ahead that the car can still stop at (or the nearest at all), respecting lockdown.
function E:nearestStop(c)
  local dir = (c.vcmd or 0) > 0 and 1 or ((c.vcmd or 0) < 0 and -1 or 0)
  local m = c.moving and motion.stopDistance(self.cfg.motion, c.vcmd or 0) or 0
  local best, bd
  for i, s in ipairs(c.stops) do
    if self:allowed(i) and (not self.lockdown or i >= self.boundary) then
      local ahead = (s - c.y) * dir
      local ok = dir == 0 or ahead >= m
      if ok then
        local dist = math.abs(s - c.y)
        if not bd or dist < bd then best, bd = i, dist end
      end
    end
  end
  if best then return best end
  for i, s in ipairs(c.stops) do
    if self:allowed(i) then
      local dist = math.abs(s - c.y)
      if not bd or dist < bd then best, bd = i, dist end
    end
  end
  return best
end

------------------------------------------------------------------------ arrival

function E:arrive(c, f)
  local td = c.dir
  c.calls[f] = nil
  local nd
  local up, down = self.hall.up[f] == c.name, self.hall.down[f] == c.name
  if td == "up" then
    if dispatch.stopsBeyond(self, c, f, "up") or up then nd = "up"
    elseif down or dispatch.stopsBeyond(self, c, f, "down") then nd = "down" end
  elseif td == "down" then
    if dispatch.stopsBeyond(self, c, f, "down") or down then nd = "down"
    elseif up or dispatch.stopsBeyond(self, c, f, "up") then nd = "up" end
  else
    if up then nd = "up" elseif down then nd = "down"
    elseif dispatch.stopsBeyond(self, c, f, "up") then nd = "up"
    elseif dispatch.stopsBeyond(self, c, f, "down") then nd = "down" end
  end
  if nd == "up" then
    if self.hall.up[f] ~= nil then self.hall.up[f] = nil end
  elseif nd == "down" then
    if self.hall.down[f] ~= nil then self.hall.down[f] = nil end
  else
    self.hall.up[f], self.hall.down[f] = nil, nil
  end
  c.dir, c.lantern = nd, nd
  local count = (nd == "up" and 1) or (nd == "down" and 2) or (td == "down" and 2) or 1
  if f == 1 then count = 1 elseif f == self.n then count = 2 end
  self:chime(c, count)
  c.openReq = true
  c.target = nil
  c.door.presses = 0
end

function E:chime(c, count)
  self:send({ type = "chime", car = c.name, count = count })
  if c.music == "play" then
    self:send({ type = "music", car = c.name, cmd = "duck" })
    c.duckUntil = self.now + self.cfg.timing.chimeDuck
  end
end

------------------------------------------------------------------------ per-car run

-- A moving car keeps the stop it is slowing down for: the next-stop search only looks beyond the stopping
-- distance, so without this the target would slip past as the car closes in. A new stop replaces it only when it
-- lies between the car and that stop (and the search found it reachable).
function E:commit(c, tgt, d)
  if c.moving and c.target and (dispatch.wants(self, c, c.target) or c.rescue or c.mode ~= "normal") then
    local s = (c.vcmd or 0) >= 0 and 1 or -1
    if (c.stops[c.target] - c.y) * s > -self.cfg.motion.levelZone then
      local closer = tgt and tgt ~= c.target and (c.stops[tgt] - c.y) * s > 0
        and (c.stops[c.target] - c.stops[tgt]) * s > 0
      if not closer then return c.target, c.dir end
      c.rescue = nil
    end
  end
  if tgt then c.rescue = nil end
  return tgt, d
end

function E:runCar(c, ci, dt)
  local mode = c.mode
  if mode == "emergency" or mode == "lockdown_trapped" or (mode == "out_of_order" and c.lock == "stopped") then
    hold(self, c)
    c.target = nil
    self:doorStep(c, ci, "close")
    return
  end
  if mode == "out_of_order" then -- a fault: no position, or the door sensor
    hold(self, c)
    c.target = nil
    self:doorStep(c, ci, "auto")
    return
  end
  if mode == "inspection" then
    c.target, c.calls = nil, {}
    self:doorStep(c, ci, "close")
    local s = (ci.inspectUp and 1 or 0) - (ci.inspectDown and 1 or 0)
    self:manualMove(c, s)
    return
  end
  if mode == "fire_hold" then
    hold(self, c)
    self:doorStep(c, ci, "hold")
    return
  end
  if mode == "fire_recall" then
    c.target = self.recall
    if c.atFloor == self.recall and not c.moving then
      c.fire = "hold"
      c.dir, c.lantern = nil, nil
      self:doorStep(c, ci, "hold")
      return
    end
    self:doorStep(c, ci, "close")
    if self:driveTo(c, self.recall, dt) then
      c.fire = "hold"
      self:chime(c, 1)
    end
    return
  end
  if mode == "firefighter" then
    self:doorStep(c, ci, "manual")
    local tgt = self:commit(c, dispatch.nextTarget(self, c))
    if tgt and c.atFloor == tgt and not c.moving then c.calls[tgt] = nil; tgt = nil end
    c.target = tgt
    if tgt then
      c.dir = c.stops[tgt] > c.y and "up" or "down"
      if self:driveTo(c, tgt, dt) then
        c.calls = {}
        c.dir, c.target = nil, nil
      end
    else
      hold(self, c)
    end
    return
  end

  -- normal service
  self:doorStep(c, ci, "auto")
  if c.door.state ~= "closed" then
    if c.moving then hold(self, c) end
    return
  end
  local tgt, d = self:commit(c, dispatch.nextTarget(self, c))
  if tgt and c.atFloor == tgt and not c.moving then
    c.dir = d or c.dir
    self:arrive(c, tgt)
    self:doorStep(c, ci, "auto")
    return
  end
  if not tgt then
    if c.moving or not c.atFloor then
      -- nothing to do but it is not at a floor: go to the nearest one it can stop at, and open there
      tgt = self:nearestStop(c)
      c.rescue = true
    else
      c.dir, c.lantern = nil, nil
    end
  end
  c.target = tgt
  if not tgt then hold(self, c); return end
  if d then c.dir = d elseif not c.moving then c.dir = c.stops[tgt] > c.y and "up" or "down" end
  if self:driveTo(c, tgt, dt) then
    if c.rescue then c.rescue = nil end
    self:arrive(c, tgt)
  end
end

------------------------------------------------------------------------ step

function E:step(now, inp)
  inp = inp or {}
  local dt = self.now and math.max(0, now - self.now) or 0
  if not self.now then for _, n in ipairs(self.order) do self.cars[n].door.since = now end end
  self.now = now
  self.messages = {}
  self:groupInputs(inp)

  -- inputs per car
  for _, name in ipairs(self.order) do
    local c, ci = self.cars[name], (inp.cars and inp.cars[name]) or {}
    self:updatePosition(c, ci)
    self:updateDoorReading(c, ci)
    c.fault = self:faultOf(c)
    c.mode = self:modeOf(c, ci)
  end

  -- Phase II: the firefighter key, in a car that is in fire service at the recall floor (or already in Phase II)
  for _, name in ipairs(self.order) do
    local c, ci = self.cars[name], (inp.cars and inp.cars[name]) or {}
    if ci.firefighter and c.fire == "hold" then c.fire = "firefighter"; c.calls = {} end
    if not ci.firefighter and c.fire == "firefighter" and not c.moving then
      c.fire = self.fireLatched and "recall" or nil
      c.calls = {}
    end
    c.mode = self:modeOf(c, ci)
  end

  for _, ev in ipairs(inp.events or {}) do self:handleEvent(ev) end

  -- hall buttons (rising edge)
  for _, d in ipairs({ "up", "down" }) do
    local key = d == "up" and "hallUp" or "hallDown"
    local cur, prev = inp[key] or {}, self.prev[key]
    for i = 1, self.n do
      if cur[i] and not prev[i] then self:hallCall(i, d) end
      prev[i] = cur[i] and true or false
    end
  end

  for _, name in ipairs(self.order) do
    local c, ci = self.cars[name], (inp.cars and inp.cars[name]) or {}
    self:safety(c, ci)
    c.mode = self:modeOf(c, ci)
    -- a car that leaves normal service gives up its hall calls
    if c.mode ~= "normal" and c.mode ~= "firefighter" then
      if c.mode ~= "out_of_order" or c.lock then c.calls = {} end
    end
    self:runCar(c, ci, dt)
    -- commanded speed history for the governor
    c.cmdHist[#c.cmdHist + 1] = { t = now, v = c.release and c.vcmd or 0 }
    trimHistory(c.cmdHist, now - self.cfg.safety.cmdWindow)
  end

  dispatch.assign(self)

  -- alarm and music
  for _, name in ipairs(self.order) do
    local c = self.cars[name]
    local on = now < c.alarmUntil
    if on ~= c.alarmOn then
      c.alarmOn = on
      self:send({ type = "alarm", car = name, on = on })
      if c.music == "play" then self:send({ type = "music", car = name, cmd = on and "duck" or "resume" }) end
    end
    if c.duckUntil and now >= c.duckUntil then
      c.duckUntil = nil
      if c.music == "play" and not c.alarmOn then self:send({ type = "music", car = name, cmd = "resume" }) end
    end
    local m = c.mode
    local want = (m == "normal" or m == "inspection" or (m == "out_of_order" and not c.lock)) and "play" or "stop"
    if want ~= c.music then
      c.music = want
      self:send({ type = "music", car = name, cmd = want })
    end
  end

  return self:outputs()
end

function E:outputs()
  local out = { cars = {}, hallUpLit = {}, hallDownLit = {}, messages = self.messages }
  for _, name in ipairs(self.order) do
    local c = self.cars[name]
    local open = c.door.state == "opening" or c.door.state == "open"
    local landing = {}
    if open and c.atFloor then landing[c.atFloor] = true end
    out.cars[name] = { rpm = c.rpm, release = c.release, doorOpen = open, landing = landing }
  end
  for i = 1, self.n do
    out.hallUpLit[i] = self.hall.up[i] ~= nil
    out.hallDownLit[i] = self.hall.down[i] ~= nil
  end
  return out
end

------------------------------------------------------------------------ views (for the cab, panel and indicators)

local MESSAGES = {
  inspection = "Inspection",
  fire_recall = "Fire - returning to G",
  fire_hold = "Fire - exit at G",
  firefighter = "Firefighter service",
  lockdown_trapped = "Lab lockdown",
  emergency = "Emergency - help is on the way",
}

function E:carState(name)
  local c = self.cars[name]
  local dir
  if c.moving and (c.vcmd or 0) ~= 0 then dir = c.vcmd > 0 and "up" or "down" else dir = c.lantern or c.dir end
  local msg
  if self.now and self.now < c.msgUntil then msg = c.msg end
  if not msg then
    if c.mode == "out_of_order" then msg = c.lock and "Out of Order" or ("Out of Order - " .. (c.fault or ""))
    elseif MESSAGES[c.mode] then msg = MESSAGES[c.mode]
    elseif c.door.state == "closing" then msg = "Doors closing" end
  end
  return {
    type = "state", car = name,
    floor = c.nearest and self.floors[c.nearest] or nil,
    dir = dir,
    doors = c.door.state,
    mode = c.mode or "normal",
    message = msg,
    next = c.target and self.floors[c.target] or nil,
    reason = c.latched or c.fault,
  }
end

function E:panelState(name)
  local c = self.cars[name]
  local lit, locked = {}, {}
  for i in pairs(c.calls) do lit[self.floors[i]] = true end
  local dead = c.mode ~= "normal" and c.mode ~= "firefighter"
  for i = 1, self.n do
    if dead or not self:allowed(i) then locked[self.floors[i]] = true end
  end
  return {
    type = "panel", car = name, lit = lit, locked = locked,
    keycard_window = (self.now or 0) < c.keycardUntil and not self.lockdown,
    mode = c.mode or "normal",
  }
end

-- What the landing indicator above floor i of car `name`'s shaft shows.
-- kind: "floor" (text = floor name, arrow = travel dir, lantern = arrival arrow), "out", "fire", "maint"
function E:indicator(name, i)
  local c = self.cars[name]
  local m = c.mode
  if m == "lockdown_trapped" or (m == "out_of_order" and c.lock) then
    if not self.lab[i] then return { kind = "out", text = "Out of Order" } end
  elseif m == "out_of_order" or m == "emergency" then
    return { kind = "out", text = "Out of Order" }
  elseif m == "inspection" then
    return { kind = "maint", text = "Maintenance" }
  elseif m == "fire_recall" or m == "fire_hold" or m == "firefighter" then
    return { kind = "fire", text = "Fire Service", floor = c.nearest and self.floors[c.nearest] }
  end
  local arrow
  if c.moving and (c.vcmd or 0) ~= 0 then arrow = c.vcmd > 0 and "up" or "down" end
  local lantern
  if c.atFloor == i and c.door.state ~= "closed" and not c.lock then lantern = c.lantern end
  return { kind = "floor", text = c.nearest and self.floors[c.nearest] or "--", arrow = arrow, lantern = lantern }
end

-- The floor whose doorway the player detector should watch for this car (nil = none).
function E:doorwayFloor(name)
  local c = self.cars[name]
  if c.door.state ~= "closed" and c.atFloor then return c.atFloor end
  return nil
end

function E:hallCalls()
  local up, down = {}, {}
  for i = 1, self.n do
    if self.hall.up[i] ~= nil then up[#up + 1] = { floor = self.floors[i], car = self.hall.up[i] or nil } end
    if self.hall.down[i] ~= nil then down[#down + 1] = { floor = self.floors[i], car = self.hall.down[i] or nil } end
  end
  return up, down
end

return E
