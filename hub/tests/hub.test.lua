-- Integration: boot hub.lua on an emulated computer with relays, two creative motors, a player detector, the
-- control panel monitor and a landing monitor (hub.world.json). It must start braked and draw the panel.
ccunit.test("hub boots, brakes both cars and draws the panel", function()
  local relay = peripheral.wrap("redstone_relay_5")
  local motor = peripheral.wrap("Create_CreativeMotor_0")
  motor.setGeneratedSpeed(32) -- left running by someone: the hub must stop it
  relay.setOutput("top", true)
  ccunit.run("hub.lua", { script = function()
    sleep(0.5)
    -- the cab of car A reports in: level at 2, doors closed
    os.queueEvent("rednet_message", 21, { type = "pos", car = "A", y = 112.0 }, "mmlift")
    os.queueEvent("rednet_message", 21, { type = "door_state", car = "A", open = false, ok = true }, "mmlift")
    sleep(1)
  end })
  ccunit.eq(motor.getGeneratedSpeed(), 0, "motor A stopped")
  ccunit.eq(peripheral.wrap("Create_CreativeMotor_1").getGeneratedSpeed(), 0, "motor B stopped")
  ccunit.eq(relay.getOutput("top"), false, "brake A set (release off)")
  local panel = ccunit.screen("monitor_0")
  ccunit.contains(panel, "MOONLIFT HUB")
  ccunit.contains(panel, "CAR A")
  ccunit.contains(panel, "CAR B")
  ccunit.contains(panel, "Hall up")
  ccunit.contains(panel, "Lockdown")
  ccunit.contains(panel, "y 112.00")
  ccunit.contains(panel, "not wired")
  ccunit.contains(ccunit.screen("monitor_6"), "Out of Order") -- car A's G sign: no door state yet when drawn, or B
end, { timeout = 20 })

