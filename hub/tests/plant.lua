-- A simulated shaft for the tests: the motor's RPM moves the car, the brake holds it, contacts light near their
-- floors, the door takes time to report its new state, GPS arrives 10 times a second rounded to 0.01, and faults can
-- be switched on (cable break, overspeed, lost GPS, dead or stuck contacts, door sensor faults, a blocked doorway).
local P = {}
P.__index = P

local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

-- start = { A = "G", B = "6" } (floor names) or heights
function P.new(cfg, start)
  local self = setmetatable({ cfg = cfg, cars = {}, now = 0 }, P)
  local index = {}
  for i, n in ipairs(cfg.floors) do index[n] = i end
  self.index = index
  for name in pairs(cfg.cars) do
    local stops = {}
    local cc = cfg.cars[name] or {}
    for i, t in ipairs(cc.thresholds or cfg.thresholds) do stops[i] = t + cfg.levelOffset end
    local s = start and start[name] or "G"
    local y = type(s) == "number" and s or stops[index[s]]
    self.cars[name] = {
      stops = stops, y = y, v = 0, rpm = 0, release = false,
      doorCmd = false, doorOpen = false, doorChangeAt = nil, doorReportT = 0,
      gpsY = round2(y), gpsT = 0, nextGps = 0,
      -- faults and test inputs
      cableBroken = false, overspeed = 1, brakeFails = false,
      jammed = false,           -- the car doesn't move whatever the winch does
      kick = nil,               -- { v = extra blocks/s, untilT = plant time }: a rope surge or bounce
      gps = "ok",               -- "ok", "nogps" (cab sends y = nil), "silent" (no messages), "frozen" (same y)
      deadContacts = {}, stuckContacts = {},
      doorSensor = "ok",        -- "ok", "fail" (ok = false), "silent" (no door_state messages)
      doorJam = false,          -- the door does not move
      blocked = false,          -- a player in the doorway
      inspect = false, inspectUp = false, inspectDown = false, firefighter = false,
      log = {},                 -- { t, y, rpm, release } every step
      maxRpm = 0,
      noContact = {},           -- floors with no contact wired
    }
  end
  self.fire, self.lockdown, self.fireReset = false, false, false
  return self
end

function P:stop(name, floor) return self.cars[name].stops[self.index[floor] or floor] end

function P:step(dt, now, out)
  local doorLag = 0.25
  for name, c in pairs(self.cars) do
    local o = out and out.cars[name] or { rpm = 0, release = false, doorOpen = false }
    c.rpm, c.release = o.rpm or 0, o.release and true or false
    if math.abs(c.rpm) > c.maxRpm then c.maxRpm = math.abs(c.rpm) end
    if c.cableBroken then
      c.v = c.v - 10 * dt -- free fall: the winch brake no longer holds the car
    else
      local braked = not c.release and not c.brakeFails
      if braked then c.v = 0 else c.v = c.rpm * self.cfg.motion.blocksPerRev / 60 * c.overspeed end
      if c.jammed then c.v = 0 end
    end
    -- a rope surge or bounce: extra speed for a moment
    if c.kick and now < c.kick.untilT then c.v = c.v + c.kick.v end
    c.y = c.y + c.v * dt
    local lo, hi = c.stops[1] - 2, c.stops[#c.stops] + 2
    if c.y < lo then c.y, c.v = lo, 0 elseif c.y > hi then c.y, c.v = hi, 0 end
    -- the door: its block state follows the command after a short lag, unless jammed or held by a player
    local want = o.doorOpen and true or false
    if want ~= c.doorCmd then c.doorCmd, c.doorChangeAt = want, now + doorLag end
    if c.doorOpen ~= c.doorCmd and not c.doorChangeAt then c.doorChangeAt = now + doorLag end
    if c.doorChangeAt and now >= c.doorChangeAt and not c.doorJam then
      if c.doorCmd or not c.blocked then c.doorOpen = c.doorCmd; c.doorChangeAt = nil end
    end
    -- GPS 10 times a second
    if now >= c.nextGps then
      c.nextGps = now + 0.1
      if c.gps == "ok" then c.gpsY, c.gpsT = round2(c.y), now
      elseif c.gps == "nogps" then c.gpsY, c.gpsT = nil, now
      elseif c.gps == "frozen" then c.gpsT = now end
    end
    if now - c.doorReportT >= 0.25 and c.doorSensor ~= "silent" then c.doorReportT = now end
    c.log[#c.log + 1] = { t = now, y = c.y, rpm = c.rpm, release = c.release }
  end
  self.now = now
end

function P:inputs(now)
  local inp = { fire = self.fire, lockdown = self.lockdown, fireReset = self.fireReset, cars = {} }
  for name, c in pairs(self.cars) do
    local contacts, wired = {}, {}
    for i, s in ipairs(c.stops) do
      wired[i] = not c.noContact[i]
      contacts[i] = wired[i] and ((math.abs(c.y - s) <= 0.4 and not c.deadContacts[i]) or c.stuckContacts[i]) or false
    end
    inp.cars[name] = {
      y = c.gpsY, yTime = c.gpsT,
      contacts = contacts, contactsWired = wired,
      door = { open = c.doorOpen, ok = c.doorSensor ~= "fail", t = c.doorReportT },
      inspect = c.inspect, inspectUp = c.inspectUp, inspectDown = c.inspectDown, firefighter = c.firefighter,
      blocked = c.blocked,
    }
  end
  return inp
end

return P
