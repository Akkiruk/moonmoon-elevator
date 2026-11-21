-- All hardware access for the hub, driven by config.lua. Nothing else touches a peripheral (panel.lua draws on the
-- monitor handed out here).
local H = {}
H.__index = H

local SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }

function H.new(cfg, per)
  local self = setmetatable({ cfg = cfg, p = per or peripheral, out = {}, motorRpm = {}, problems = {} }, H)
  self.lastRefresh = -1e9
  self.order = {}
  for _, n in ipairs(cfg.carOrder) do if cfg.cars[n] then self.order[#self.order + 1] = n end end
  return self
end

-- Signal spec -> a readable key for errors.
local function key(sig) return tostring(sig[1]) .. ":" .. tostring(sig[2]) .. (sig[3] and (":" .. sig[3]) or "") end

function H:wrap(name)
  if name == nil then return nil end
  if name == "computer" then return redstone end
  if not self.p.isPresent(name) then return nil end
  return self.p.wrap(name)
end

function H:problem(sig, what) self.problems[key(sig)] = what end

-- Read one input signal: true, false; and whether it is wired (the peripheral exists).
function H:input(sig)
  if not sig then return false, false end
  local dev = self:wrap(sig[1])
  if not dev or not SIDES[sig[2]] then self:problem(sig, "missing"); return false, false end
  local ok, v
  if sig[3] then
    ok, v = pcall(dev.getBundledInput, sig[2])
    if ok then v = colors.test(v, sig[3]) end
  else
    ok, v = pcall(dev.getInput, sig[2])
  end
  if not ok then self:problem(sig, "error"); return false, false end
  self.problems[key(sig)] = nil
  v = v and true or false
  if sig.invert then v = not v end
  return v, true
end

-- Set one output signal; only writes when the value changed (or on the periodic refresh).
function H:output(sig, value, force)
  if not sig then return end
  value = value and true or false
  if sig.invert then value = not value end
  local k = key(sig)
  if not force and self.out[k] == value then return end
  local dev = self:wrap(sig[1])
  if not dev or not SIDES[sig[2]] then self:problem(sig, "missing"); self.out[k] = nil; return end
  local ok
  if sig[3] then
    ok = pcall(function()
      local cur = dev.getBundledOutput(sig[2])
      dev.setBundledOutput(sig[2], value and colors.combine(cur, sig[3]) or colors.subtract(cur, sig[3]))
    end)
  else
    ok = pcall(dev.setOutput, sig[2], value)
  end
  if ok then self.out[k] = value; self.problems[k] = nil else self:problem(sig, "error"); self.out[k] = nil end
end

-- Everything the controller reads from redstone, as the `inputs` table of elevator.lua. Positions, door state,
-- the doorway check and the rednet events get merged in by hub.lua.
function H:read()
  local cfg = self.cfg
  local n = #cfg.floors
  local inp = { cars = {} }
  inp.fire = self:input(cfg.fireAlarm)
  inp.lockdown = self:input(cfg.lockdown)
  inp.fireReset = self:input(cfg.fireReset)
  for _, name in ipairs(self.order) do
    local cc = cfg.cars[name]
    local ci = { contacts = {}, contactsWired = {} }
    for i = 1, n do
      ci.contacts[i], ci.contactsWired[i] = self:input(cc.contacts and cc.contacts[i])
    end
    ci.inspect = self:input(cc.inspect)
    ci.inspectUp = self:input(cc.inspectUp)
    ci.inspectDown = self:input(cc.inspectDown)
    ci.firefighter = self:input(cc.firefighter)
    inp.cars[name] = ci
  end
  return inp
end

-- Apply the controller's outputs. The motor and the brake go first, so a stop is never held up by a lamp.
function H:write(out, now)
  local cfg = self.cfg
  local force = false
  if now and now - self.lastRefresh >= 5 then force, self.lastRefresh = true, now end
  for _, name in ipairs(self.order) do
    local cc, o = cfg.cars[name], out.cars[name]
    if o then
      local rpm = (o.release and o.rpm or 0) * (cc.motorSign or 1)
      if not o.release then self:output(cc.brakeRelease, false, force) end
      self:setMotor(name, rpm, force)
      if o.release then self:output(cc.brakeRelease, true, force) end
      self:output(cc.doorOpen, o.doorOpen, force)
      for i = 1, #cfg.floors do
        self:output(cc.landingDoors and cc.landingDoors[i], o.landing[i], force)
      end
    end
  end
end

function H:setMotor(name, rpm, force)
  local cc = self.cfg.cars[name]
  if not force and self.motorRpm[name] == rpm then return end
  local m = self:wrap(cc.motor)
  local sig = { cc.motor, "motor" }
  if not m then self:problem(sig, "missing"); self.motorRpm[name] = nil; return end
  local ok = pcall(m.setGeneratedSpeed, rpm)
  if ok then self.motorRpm[name] = rpm; self.problems[key(sig)] = nil
  else self:problem(sig, "error"); self.motorRpm[name] = nil end
end

-- Stop both motors and set every brake. Used at start-up and on a crash.
function H:safeStop()
  for _, name in ipairs(self.order) do
    local cc = self.cfg.cars[name]
    self:output(cc.brakeRelease, false, true)
    self:setMotor(name, 0, true)
    self:output(cc.doorOpen, false, true)
  end
end

-- Is a player in the doorway of floor i of this car's shaft? (AP call: waits a server tick, so run it in its own
-- coroutine.) Returns nil when there is no detector or no box for that floor.
function H:doorway(name, i)
  local box = self.cfg.cars[name].doorways and self.cfg.cars[name].doorways[i]
  if not box then return nil end
  local det = self:wrap(self.cfg.detector)
  if not det or not det.getPlayersInCoords then return nil end
  -- the box lists whole blocks, the detector's far corner is exclusive: +1 so a player standing in the last block
  -- (it missed one at x = 47.0 in the test shaft) still counts
  local ok, list = pcall(det.getPlayersInCoords,
    { x = box[1], y = box[2], z = box[3] }, { x = box[4] + 1, y = box[5] + 1, z = box[6] + 1 })
  if not ok or type(list) ~= "table" then return nil end
  return #list > 0
end

function H:monitor()
  local m = self:wrap(self.cfg.monitor)
  if m and m.setTextScale then return m end
  return nil
end

function H:openModem()
  local side = self.cfg.modem
  if side then
    if not rednet.isOpen(side) then pcall(rednet.open, side) end
    return rednet.isOpen(side)
  end
  local found = false
  for _, n in ipairs(self.p.getNames()) do
    if self.p.getType(n) == "modem" then
      local m = self.p.wrap(n)
      if m.isWireless and m.isWireless() then
        if not rednet.isOpen(n) then pcall(rednet.open, n) end
        found = true
      end
    end
  end
  return found
end

-- Signals that could not be read or written (missing peripheral, bad side), as a sorted list of "name:side".
function H:problemList()
  local l = {}
  for k in pairs(self.problems) do l[#l + 1] = k end
  table.sort(l)
  return l
end

return H
