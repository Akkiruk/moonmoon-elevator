-- Test harness: the controller (elevator.lua) wired to the simulated shaft (tests/plant.lua) on a virtual clock.
-- Nothing here sleeps: a minute of shaft time runs in a fraction of a real second.
local Elevator = require "elevator"
local Plant = require "tests.plant"

local H = {}
local W = {}
W.__index = W

local function copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = copy(v) end
  return o
end

-- opts.start = { A = "G", B = "6" }; opts.config = function(cfg) ... end to tweak a copy of config.lua
function H.world(opts)
  opts = opts or {}
  local cfg = copy(require "config")
  if opts.config then opts.config(cfg) end
  local w = setmetatable({
    cfg = cfg, now = 0, dt = 0.05, steps = 0,
    msgs = {}, events = {}, hallUp = {}, hallDown = {},
  }, W)
  w.ctl = Elevator.new(cfg)
  w.plant = Plant.new(cfg, opts.start or { A = "G", B = "G" })
  w.index = w.plant.index
  w:run(opts.warmup or 3)
  return w
end

function W:step()
  local inp = self.plant:inputs(self.now)
  inp.events, self.events = self.events, {}
  inp.hallUp, inp.hallDown = {}, {}
  for i, untilT in pairs(self.hallUp) do inp.hallUp[i] = self.now < untilT end
  for i, untilT in pairs(self.hallDown) do inp.hallDown[i] = self.now < untilT end
  self.out = self.ctl:step(self.now, inp)
  for _, m in ipairs(self.out.messages) do
    m.at = self.now
    self.msgs[#self.msgs + 1] = m
  end
  self.now = self.now + self.dt
  self.plant:step(self.dt, self.now, self.out)
  self.steps = self.steps + 1
  if self.steps % 400 == 0 then os.queueEvent("harness_yield"); os.pullEvent("harness_yield") end
end

function W:run(seconds)
  local stop = self.now + seconds
  while self.now < stop - 1e-9 do self:step() end
end

-- Run until fn(w) is true; returns true, or false after max seconds.
function W:runUntil(fn, max)
  local stop = self.now + (max or 120)
  while self.now < stop do
    if fn(self) then return true end
    self:step()
  end
  return fn(self) and true or false
end

function W:fi(f) return type(f) == "number" and f or self.index[f] end

function W:call(car, floor) self.events[#self.events + 1] = { type = "call", car = car, floor = floor } end
function W:door(car, cmd) self.events[#self.events + 1] = { type = "door", car = car, cmd = cmd } end
function W:keycard(car) self.events[#self.events + 1] = { type = "keycard", car = car } end
function W:alarmButton(car) self.events[#self.events + 1] = { type = "alarm_button", car = car } end
function W:reset(car) self.events[#self.events + 1] = { type = "reset", car = car } end

function W:hall(floor, dir)
  local t = dir == "up" and self.hallUp or self.hallDown
  t[self:fi(floor)] = self.now + 0.2
end

function W:car(name) return self.ctl.cars[name] end
function W:p(name) return self.plant.cars[name] end
function W:y(name) return self.plant.cars[name].y end
function W:state(name) return self.ctl:carState(name) end
function W:mode(name) return self.ctl.cars[name].mode end
function W:doors(name) return self.ctl.cars[name].door.state end

function W:offset(name, floor) return self:y(name) - self.plant:stop(name, floor) end
function W:levelAt(name, floor)
  local c = self.ctl.cars[name]
  return math.abs(self:offset(name, floor)) <= 1 / 16 and not c.moving
end
function W:still(name) return not self.ctl.cars[name].moving and self.plant.cars[name].v == 0 end

-- Waits until the car is level and stopped at floor, with its doors open.
function W:arriveOpen(name, floor, max)
  return self:runUntil(function(w) return w:levelAt(name, floor) and w:doors(name) == "open" end, max or 90)
end

function W:messagesOf(kind, car, since)
  local l = {}
  for _, m in ipairs(self.msgs) do
    if m.type == kind and (car == nil or m.car == car) and (since == nil or m.at >= since) then l[#l + 1] = m end
  end
  return l
end

return H
