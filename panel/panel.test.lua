-- Run from this folder: craftos-mcp test panel.test.lua
-- The reader's redstone input is panel.cardInput and the outgoing messages panel.send, so tests fake them.
-- Touches are real monitor_touch events on the 1x2 monitor "front".
local panel = require "panel"

local sent, card
local function setup(silence)
  sent, card = {}, false
  panel.config.car = "A"
  panel.config.silence = silence or 30
  panel.send = function(m) sent[#sent + 1] = m end
  panel.cardInput = function() return card end
end

local function with(f) parallel.waitForAny(panel.run, function() f() end) end

local function feed(msg)
  os.queueEvent("rednet_message", 9, msg, "mmlift")
  sleep(0.15)
end

local function hubPanel(t)
  local m = { type = "panel", car = "A", lit = {}, locked = {}, keycard_window = false, mode = "normal" }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

local function button(id)
  for _, b in ipairs(panel.layout(panel.size[1], panel.size[2])) do if b.id == id then return b end end
end

local function tap(id)
  local b = button(id)
  os.queueEvent("monitor_touch", "front", b.x1 + 2, b.y1 + 1)
  sleep(0.15)
end

local function rowText(y)
  local t = {}
  for x = 1, panel.size[1] do t[x] = panel.frame[y][x][1] end
  return table.concat(t)
end

local function bgAt(id, dy) local b = button(id); return panel.frame[b.y1 + (dy or 1)][b.x1 + 3][3] end

ccunit.test("monitor is 15x24 and the 14 buttons fit", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(panel.size[1], 15)
  ccunit.eq(panel.size[2], 24)
  local list = panel.layout(15, 24)
  ccunit.eq(#list, 14)
  for _, b in ipairs(list) do ccunit.truthy(b.x1 >= 1 and b.x2 <= 15 and b.y1 >= 3 and b.y2 <= 24, b.id) end
  -- bottom to top: L1 is lowest, 6 is highest
  ccunit.truthy(button("L1").y1 > button("G").y1)
  ccunit.truthy(button("G").y1 > button("6").y1)
end, { timeout = 10 })

ccunit.test("hello at boot, as the panel", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(sent[1].type, "hello")
  ccunit.eq(sent[1].role, "panel")
  ccunit.eq(sent[1].car, "A")
end, { timeout = 10 })

ccunit.test("touches send call, door and alarm_button", function()
  setup()
  with(function()
    feed(hubPanel())
    sent = {}
    tap("P1"); tap("6")
    ccunit.eq(sent[1], { type = "call", car = "A", floor = "P1" })
    ccunit.eq(sent[2], { type = "call", car = "A", floor = "6" })
    tap("open"); tap("close"); tap("alarm")
    ccunit.eq(sent[3], { type = "door", car = "A", cmd = "open" })
    ccunit.eq(sent[4], { type = "door", car = "A", cmd = "close" })
    ccunit.eq(sent[5], { type = "alarm_button", car = "A" })
    os.queueEvent("monitor_touch", "front", 8, 2) -- on the banner: nothing
    sleep(0.2)
    ccunit.eq(#sent, 5)
    os.queueEvent("monitor_touch", "other", 3, 4)
    sleep(0.2)
    ccunit.eq(#sent, 5)
  end)
end, { timeout = 15 })

ccunit.test("lit buttons glow amber, idle ones are steel", function()
  setup()
  with(function()
    feed(hubPanel({ lit = { ["3"] = true, G = true } }))
    ccunit.eq(bgAt("3"), colors.orange)
    ccunit.eq(bgAt("G"), colors.orange)
    ccunit.eq(bgAt("4"), colors.lightGray)
    ccunit.contains(rowText(button("3").y1 + 1), "3")
    feed(hubPanel({ lit = {} }))
    ccunit.eq(bgAt("3"), colors.lightGray)
  end)
end, { timeout = 10 })

ccunit.test("locked buttons are dimmed; keyed floors show LOCKED, then OPEN in the card window", function()
  setup()
  with(function()
    feed(hubPanel({ locked = { ["5"] = true } }))
    ccunit.eq(bgAt("5"), colors.gray)
    ccunit.eq(panel.frame[button("5").y1 + 1][button("5").x1 + 3][2], colors.lightGray)
    ccunit.eq(bgAt("4"), colors.lightGray)
    ccunit.contains(rowText(button("L1").y2), "LOCKED")
    ccunit.contains(rowText(button("L2").y2), "LOCKED")
    ccunit.eq(bgAt("L1"), colors.gray)
    feed(hubPanel({ keycard_window = true }))
    ccunit.contains(rowText(button("L1").y2), "OPEN")
    ccunit.eq(bgAt("L1"), colors.lightGray)
    ccunit.contains(rowText(2), "CARD OK")
    feed(hubPanel({ keycard_window = true, locked = { L1 = true, L2 = true }, mode = "lockdown_trapped" }))
    ccunit.contains(rowText(button("L1").y2), "LOCKED")
    ccunit.contains(rowText(1), "LOCKDOWN")
  end)
end, { timeout = 10 })

ccunit.test("mode banners", function()
  setup()
  with(function()
    feed(hubPanel())
    ccunit.contains(rowText(1), "CAR A")
    feed(hubPanel({ mode = "inspection" }))
    ccunit.contains(rowText(1), "INSPECTION")
    ccunit.eq(panel.frame[1][2][3], colors.orange)
    feed(hubPanel({ mode = "fire_recall" }))
    ccunit.contains(rowText(1), "FIRE RECALL")
    ccunit.eq(panel.frame[1][2][3], colors.red)
  end)
end, { timeout = 10 })

ccunit.test("keycard: one message per rising edge", function()
  setup()
  with(function()
    feed(hubPanel())
    sent = {}
    sleep(0.2)
    ccunit.eq(#sent, 0, "no message while the input is low")
    card = true; sleep(0.3)
    ccunit.eq(#sent, 1)
    ccunit.eq(sent[1], { type = "keycard", car = "A" })
    sleep(0.5)
    ccunit.eq(#sent, 1, "held high is one swipe")
    card = false; sleep(0.3)
    ccunit.eq(#sent, 1, "falling edge sends nothing")
    card = true; sleep(0.3)
    ccunit.eq(#sent, 2)
  end)
end, { timeout = 15 })

ccunit.test("no hub: Out of Order, buttons dead and silent; hub back restores", function()
  setup(1)
  with(function()
    feed(hubPanel({ lit = { ["3"] = true } }))
    ccunit.eq(bgAt("3"), colors.orange)
    sleep(1.6)
    ccunit.contains(rowText(1), "OUT OF ORDER")
    ccunit.eq(bgAt("3"), colors.gray)
    sent = {}
    tap("3"); tap("open")
    ccunit.eq(#sent, 0)
    feed(hubPanel())
    ccunit.contains(rowText(1), "CAR A")
    tap("2")
    ccunit.eq(sent[#sent].floor, "2")
  end)
end, { timeout = 15 })

ccunit.test("starts as Out of Order if the hub never speaks", function()
  setup(1)
  with(function() sleep(1.6) end)
  ccunit.contains(rowText(1), "OUT OF ORDER")
end, { timeout = 10 })

ccunit.test("panel messages for the other car are ignored", function()
  setup()
  with(function()
    feed(hubPanel({ lit = { ["3"] = true } }))
    feed(hubPanel({ car = "B", lit = { ["4"] = true } }))
    ccunit.eq(bgAt("4"), colors.lightGray)
    ccunit.eq(bgAt("3"), colors.orange)
  end)
end, { timeout = 10 })

ccunit.test("firefighter key: hidden by default, shown when allowed or on, toggles with a touch", function()
  setup()
  with(function()
    feed(hubPanel())
    ccunit.eq(#panel.layout(15, 24), 14, "hidden")
    feed(hubPanel({ fireKeyAllowed = true, mode = "fire_hold" }))
    ccunit.eq(#panel.layout(15, 24), 15, "offered")
    local fb = button("firefighter")
    ccunit.eq(panel.frame[fb.y1][fb.x1 + 1][3], colors.red)
    ccunit.contains(rowText(fb.y1), "FIRE")
    ccunit.contains(rowText(fb.y2), "KEY")
    -- it sits beside the top floor button, inside the screen
    ccunit.truthy(fb.x2 <= 15 and fb.y1 == button("6").y1 and fb.x1 > button("6").x2)
    sent = {}
    tap("firefighter")
    ccunit.eq(sent[1], { type = "firefighter", car = "A", on = true })
    feed(hubPanel({ firefighter = true, fireKeyAllowed = false, mode = "firefighter" }))
    ccunit.eq(#panel.layout(15, 24), 15, "stays while on")
    ccunit.eq(panel.frame[fb.y1 + 1][fb.x1 + 1][3], colors.orange, "amber when on")
    ccunit.contains(rowText(fb.y2), "ON")
    sent = {}
    tap("firefighter")
    ccunit.eq(sent[1], { type = "firefighter", car = "A", on = false })
    feed(hubPanel())
    ccunit.eq(#panel.layout(15, 24), 14, "hidden again")
    sent = {}
    os.queueEvent("monitor_touch", "front", fb.x1 + 2, fb.y1 + 1)
    sleep(0.2)
    ccunit.eq(#sent, 0, "a hidden key does nothing")
  end)
end, { timeout = 15 })

ccunit.test("firefighter key is hidden when the hub is silent", function()
  setup(1)
  with(function()
    feed(hubPanel({ firefighter = true }))
    ccunit.eq(#panel.layout(15, 24), 15)
    sleep(1.6)
    ccunit.eq(#panel.layout(15, 24), 14)
  end)
end, { timeout = 10 })
