-- Door sensor computer, next to the car door. Reads the block reader in front of the door and outputs a
-- redstone level on top for the cab computer: 15 = door open, 8 = closed, 0 = reader missing or read failed.
while true do
  local level = 0
  local reader = peripheral.find("block_reader")
  if reader then
    local ok, states = pcall(reader.getBlockStates)
    if ok and type(states) == "table" and states.open ~= nil then
      level = (states.open == true) and 15 or 8
    end
  end
  redstone.setAnalogOutput("top", level)
  sleep(0.1)
end
