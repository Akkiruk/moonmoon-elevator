-- Screenshot helper: `shot off|on|jog|nohub` draws the station with a sample hub state.
local inspect = require "inspect"
local mode = ({ ... })[1] or "off"
inspect.config.car = "A"
inspect.send = function() end
inspect.config.silence = 3
parallel.waitForAny(inspect.run, function()
  sleep(0.3)
  local function state(m)
    os.queueEvent("rednet_message", 9, { type = "state", car = "A", floor = "4", mode = m }, "mmlift")
    sleep(0.2)
  end
  local function tap(x, y) os.queueEvent("monitor_touch", "front", x, y); sleep(0.2) end
  if mode == "off" then state("normal")
  elseif mode == "on" then state("normal"); tap(8, 4); state("inspection")
  elseif mode == "jog" then state("normal"); tap(8, 4); state("inspection"); tap(3, 8)
  else sleep(3.5) end
  sleep(0.3)
end)
