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

-- the cap colour of a button (drawn as the foreground of its right-hand cell)
local function capAt(id) local b = button(id); return panel.frame[b.y1 + 1][b.bx2][2] end

local function screenText()
  local t = {}
  for y = 1, panel.size[2] do t[#t + 1] = rowText(y) end
  return table.concat(t, "\n")
end

ccunit.test("monitor is 15x24 and the 15 buttons fit", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(panel.size[1], 15)
  ccunit.eq(panel.size[2], 24)
  local list = panel.layout(15, 24)
  ccunit.eq(#list, 15)
  for _, b in ipairs(list) do ccunit.truthy(b.x1 >= 1 and b.x2 <= 15 and b.y1 >= 3 and b.y2 <= 24, b.id) end
  -- three to a row, counting up from the bottom left like a real car panel
  ccunit.truthy(button("L1").y1 > button("G").y1)
  ccunit.truthy(button("G").y1 > button("6").y1)
  ccunit.eq(button("L1").y1, button("P3").y1)
  ccunit.truthy(button("L1").x1 < button("L2").x1 and button("L2").x1 < button("P3").x1)
  ccunit.truthy(button("open").y1 > button("L1").y1 and button("hold").y1 > button("open").y1)
end, { timeout = 10 })

ccunit.test("hello at boot, as the panel", function()
  setup()
  with(function() sleep(0.3) end)
  ccunit.eq(sent[1].type, "hello")
  ccunit.eq(sent[1].role, "panel")
  ccunit.eq(sent[1].car, "A")
end, { timeout = 10 })

ccunit.test("touches send call, door, hold and alarm_button", function()
  setup()
  with(function()
    feed(hubPanel())
    sent = {}
    tap("P1"); tap("6")
    ccunit.eq(sent[1], { type = "call", car = "A", floor = "P1" })
    ccunit.eq(sent[2], { type = "call", car = "A", floor = "6" })
    tap("open"); tap("close"); tap("alarm"); tap("hold")
    ccunit.eq(sent[3], { type = "door", car = "A", cmd = "open" })
    ccunit.eq(sent[4], { type = "door", car = "A", cmd = "close" })
    ccunit.eq(sent[5], { type = "alarm_button", car = "A" })
    ccunit.eq(sent[6], { type = "door", car = "A", cmd = "hold" })
    os.queueEvent("monitor_touch", "front", 8, 2) -- on the banner: nothing
    sleep(0.2)
    ccunit.eq(#sent, 6)
    os.queueEvent("monitor_touch", "other", 3, 5)
    sleep(0.2)
    ccunit.eq(#sent, 6)
  end)
end, { timeout = 15 })

ccunit.test("lit buttons glow yellow, idle ones are white; G has the star", function()
  setup()
  with(function()
    feed(hubPanel({ lit = { ["3"] = true, G = true } }))
    ccunit.eq(capAt("3"), colors.yellow)
    ccunit.eq(capAt("G"), colors.yellow)
    ccunit.eq(capAt("4"), colors.white)
    ccunit.contains(rowText(button("3").y1 + 1), "3")
    ccunit.contains(rowText(button("G").y1 + 1), "*G")
    feed(hubPanel({ lit = {} }))
    ccunit.eq(capAt("3"), colors.white)
  end)
end, { timeout = 10 })

ccunit.test("no LOCKED text: a press lights up, then goes dark if the hub doesn't take it", function()
  setup()
  with(function()
    feed(hubPanel({ locked = { L1 = true, L2 = true } }))
    ccunit.eq(screenText():find("LOCKED"), nil, "no LOCKED text")
    ccunit.eq(screenText():find("OPEN"), nil, "no OPEN text")
    ccunit.eq(capAt("L1"), colors.white, "a keyed floor looks like any other")
    tap("L1")
    ccunit.eq(capAt("L1"), colors.yellow, "lit as soon as it's pressed")
    sleep(1.2)
    ccunit.eq(capAt("L1"), colors.white, "dark again: no card, the hub didn't light it")
    -- with the card the hub takes the call and it stays lit
    feed(hubPanel({ keycard_window = true }))
    ccunit.contains(rowText(2), "CARD OK")
    tap("L2")
    feed(hubPanel({ keycard_window = true, lit = { L2 = true } }))
    sleep(1.2)
    ccunit.eq(capAt("L2"), colors.yellow, "still lit after the press runs out")
  end)
end, { timeout = 15 })

ccunit.test("door hold lights while the hub is holding", function()
  setup()
  with(function()
    feed(hubPanel())
    ccunit.eq(capAt("hold"), colors.white)
    ccunit.contains(rowText(button("hold").y1 + 1), "HOLD")
    feed(hubPanel({ hold = true }))
    ccunit.eq(capAt("hold"), colors.yellow)
    feed(hubPanel({ hold = false }))
    ccunit.eq(capAt("hold"), colors.white)
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
    ccunit.eq(capAt("3"), colors.yellow)
    sleep(1.6)
    ccunit.contains(rowText(1), "OUT OF ORDER")
    ccunit.eq(capAt("3"), colors.gray)
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
    ccunit.eq(capAt("4"), colors.white)
    ccunit.eq(capAt("3"), colors.yellow)
  end)
end, { timeout = 10 })

ccunit.test("firefighter key: hidden by default, shown when allowed or on, toggles with a touch", function()
  setup()
  with(function()
    feed(hubPanel())
    ccunit.eq(#panel.layout(15, 24), 15, "hidden")
    feed(hubPanel({ fireKeyAllowed = true, mode = "fire_hold" }))
    ccunit.eq(#panel.layout(15, 24), 16, "offered")
    local fb = button("firefighter")
    ccunit.eq(panel.frame[fb.y1 + 1][fb.lx][3], colors.red)
    ccunit.contains(rowText(fb.y1 + 1), "FS")
    ccunit.eq(capAt("firefighter"), colors.white)
    -- it sits beside the top floor button, inside the screen
    ccunit.truthy(fb.x2 <= 15 and fb.y1 == button("6").y1 and fb.x1 > button("6").x2)
    sent = {}
    tap("firefighter")
    ccunit.eq(sent[1], { type = "firefighter", car = "A", on = true })
    feed(hubPanel({ firefighter = true, fireKeyAllowed = false, mode = "firefighter" }))
    ccunit.eq(#panel.layout(15, 24), 16, "stays while on")
    ccunit.eq(capAt("firefighter"), colors.yellow, "amber when on")
    sent = {}
    tap("firefighter")
    ccunit.eq(sent[1], { type = "firefighter", car = "A", on = false })
    feed(hubPanel())
    ccunit.eq(#panel.layout(15, 24), 15, "hidden again")
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
    ccunit.eq(#panel.layout(15, 24), 16)
    sleep(1.6)
    ccunit.eq(#panel.layout(15, 24), 15)
  end)
end, { timeout = 10 })

ccunit.test("a monitor put back at text scale 1 gets set up again and shows the whole panel", function()
  setup()
  with(function()
    feed(hubPanel())
    panel.mon.setTextScale(1) -- what a freshly placed monitor starts at
    sleep(0.3)
    ccunit.eq(panel.mon.getTextScale(), 0.5)
    ccunit.eq(panel.size[1], 15); ccunit.eq(panel.size[2], 24)
    os.queueEvent("peripheral", "front")
    sleep(0.3)
    ccunit.eq(panel.size[1], 15)
    ccunit.contains(rowText(1), "CAR A")
  end)
end, { timeout = 10 })
