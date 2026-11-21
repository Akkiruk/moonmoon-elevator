-- Boots hub.lua on an emulated computer with relays, two creative motors, a player detector and the control panel
-- monitor (hub.world.json). It has to start braked, draw the panel, take a landing's hall call and answer the
-- landings.
ccunit.test("hub boots, brakes the car, draws the panel and talks to the landings", function()
  local relay = peripheral.wrap("redstone_relay_5")
  local motor = peripheral.wrap("Create_CreativeMotor_0")
  motor.setGeneratedSpeed(32) -- left running by someone: the hub must stop it
  relay.setOutput("top", true)
  local sent = {}
  local realBroadcast = rednet.broadcast
  rednet.broadcast = function(msg, proto) sent[#sent + 1] = msg; return realBroadcast(msg, proto) end
  ccunit.run("hub.lua", { script = function()
    sleep(0.5)
    os.queueEvent("rednet_message", 21, { type = "pos", car = "A", y = 112.0 }, "mmlift")
    os.queueEvent("rednet_message", 21, { type = "door_state", car = "A", open = false, ok = true }, "mmlift")
    os.queueEvent("rednet_message", 30, { type = "hello", role = "landing", floor = "G" }, "mmlift")
    os.queueEvent("rednet_message", 30, { type = "hall", floor = "G", dir = "up" }, "mmlift")
    sleep(1)
  end })
  rednet.broadcast = realBroadcast
  ccunit.eq(motor.getGeneratedSpeed(), 0, "motor A stopped")
  ccunit.eq(relay.getOutput("top"), false, "brake A set (release off)")
  local panel = ccunit.screen("monitor_0")
  ccunit.contains(panel, "MOONLIFT HUB")
  ccunit.contains(panel, "CAR A")
  ccunit.contains(panel, "Hall up   G")
  ccunit.contains(panel, "Lockdown")
  ccunit.contains(panel, "y 112.00")
  ccunit.contains(panel, "not wired")
  local landings, floors, lit = 0, {}, false
  for _, m in ipairs(sent) do
    if m.type == "landing" then
      landings = landings + 1
      floors[m.floor] = true
      ccunit.eq(m.car, "A", "car B is not configured")
      if m.floor == "G" and m.up then lit = true end
    end
  end
  ccunit.truthy(landings >= 11, "landing messages: " .. landings)
  ccunit.truthy(floors.L1 and floors.G and floors["6"], "every floor")
  ccunit.truthy(lit, "G's up button lit")
end, { timeout = 20 })
