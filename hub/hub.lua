-- Moonlift hub: the machine-room computer that runs both cars.
-- Reads the relays and the cabs' rednet messages, steps the controller (elevator.lua), drives the motors, brakes and
-- doors, answers the cabs, panels and landing computers, and draws the control panel.
local cfg = require "config"
local Elevator = require "elevator"
local HW = require "hw"
local panel = require "panel"

local hw = HW.new(cfg)
local ctl = Elevator.new(cfg)
local T = cfg.timing

local pos, door, blocked, events = {}, {}, {}, {}
local lastState, lastPanel, lastSentAt = {}, {}, {}
local lastLanding, landingAt = {}, {}
local targets = {}

local function clock() return os.clock() end

local function send(msg) rednet.broadcast(msg, cfg.protocol) end

local function netLoop()
  while true do
    local _, msg = rednet.receive(cfg.protocol)
    if type(msg) == "table" and msg.type == "hall" then
      events[#events + 1] = msg
    elseif type(msg) == "table" and msg.type == "hello" and msg.role == "landing" then
      lastLanding[tostring(msg.floor)] = nil
    elseif type(msg) == "table" and cfg.cars[msg.car] then
      local t = msg.type
      if t == "pos" then
        pos[msg.car] = { y = type(msg.y) == "number" and msg.y or nil, t = clock() }
      elseif t == "door_state" then
        door[msg.car] = { open = msg.open and true or false, ok = msg.ok and true or false, t = clock() }
      elseif t == "hello" then
        lastState[msg.car], lastPanel[msg.car] = nil, nil
      elseif t == "call" or t == "door" or t == "alarm_button" or t == "keycard" then
        events[#events + 1] = msg
      end
    end
  end
end

-- The doorway check calls the AP player detector, which waits a server tick, so it runs on its own.
local function detectorLoop()
  while true do
    for _, name in ipairs(ctl.order) do
      local f = ctl.now and ctl:doorwayFloor(name)
      if f then blocked[name] = hw:doorway(name, f) or false else blocked[name] = false end
    end
    sleep(0.05)
  end
end

local function touchLoop()
  while true do
    local _, side, x, y = os.pullEvent("monitor_touch")
    if side == cfg.monitor then
      for _, tg in ipairs(targets) do
        if y == tg[3] and x >= tg[1] and x <= tg[2] then events[#events + 1] = tg[4] end
      end
    end
  end
end

local function same(a, b) return textutils.serialize(a) == textutils.serialize(b) end

local function drawAll()
  local m = hw:monitor()
  if m then
    m.setTextScale(cfg.monitorScale or 0.5)
    targets = panel.drawPanel(m, ctl, { problems = hw:problemList() })
  end
end

-- one landing message per car per floor; a landing that says hello gets its floor resent
local function sendLandings(now)
  for i, f in ipairs(cfg.floors) do
    local msgs = {}
    for _, name in ipairs(ctl.order) do msgs[#msgs + 1] = ctl:landingState(name, i) end
    local key = textutils.serialize(msgs)
    if key ~= lastLanding[f] or not landingAt[f] or now - landingAt[f] >= 2 then
      lastLanding[f], landingAt[f] = key, now
      for _, m in ipairs(msgs) do send(m) end
    end
  end
end

local function controlLoop()
  local lastDraw = -1
  while true do
    local now = clock()
    local inp = hw:read()
    for name, ci in pairs(inp.cars) do
      local p = pos[name]
      ci.y, ci.yTime = p and p.y, p and p.t
      ci.door = door[name]
      ci.blocked = blocked[name]
    end
    inp.events, events = events, {}
    local out = ctl:step(now, inp)
    hw:write(out, now)
    for _, msg in ipairs(out.messages) do send(msg) end
    sendLandings(now)
    for _, name in ipairs(ctl.order) do
      local st, pn = ctl:carState(name), ctl:panelState(name)
      local due = not lastSentAt[name] or now - lastSentAt[name] >= T.stateEvery
      if due or not same(st, lastState[name]) then send(st); lastState[name] = st end
      if due or not same(pn, lastPanel[name]) then send(pn); lastPanel[name] = pn end
      if due then lastSentAt[name] = now end
    end
    if now - lastDraw >= 0.25 then lastDraw = now; drawAll() end
    sleep(T.tick)
  end
end

local function main()
  hw:safeStop()
  if not hw:openModem() then print("hub: no wireless modem found; the cabs cannot reach the hub") end
  print("Moonlift hub running. Cars: " .. table.concat(ctl.order, ", "))
  parallel.waitForAny(netLoop, detectorLoop, touchLoop, controlLoop)
end

local ok, err = pcall(main)
-- anything that stops the controller must leave the cars braked
pcall(function() hw:safeStop() end)
if not ok then
  printError("hub stopped: " .. tostring(err))
  local m = hw:monitor()
  if m then
    m.setBackgroundColor(colors.red); m.setTextColor(colors.white); m.clear()
    m.setCursorPos(1, 1); m.write("HUB ERROR - cars braked")
    m.setCursorPos(1, 2); m.write(tostring(err):sub(1, 200))
  end
  if not (ccunit or _G.HUB_NO_REBOOT) then sleep(10); os.reboot() end
  error(err, 0)
end
