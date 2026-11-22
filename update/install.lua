-- Sets up a fresh elevator computer in one go. On the new computer (ender modem on it, monitor touching it):
--
--   wget run https://raw.githubusercontent.com/Akkiruk/moonmoon-elevator/main/update/install.lua
--
-- That makes it a hall call station (the shared call button between the two lifts). A role after the url installs
-- that role instead (landing also needs car.txt afterwards). It finds the floor from GPS and asks you to confirm it,
-- then pulls the updater, installs the role and reboots. After that the updater keeps it current on its own.

local M = {
  base = "https://raw.githubusercontent.com/Akkiruk/moonmoon-elevator/main/",
  -- each floor's landing height (the hub's thresholds); a computer belongs to the floor it sits at or just above
  floors = { { "L1", 66 }, { "L2", 72 }, { "P3", 86 }, { "P2", 91 }, { "P1", 96 }, { "G", 105 },
             { "2", 109 }, { "3", 113 }, { "4", 117 }, { "5", 121 }, { "6", 125 } },
}

function M.floorAt(y)
  local best
  for _, f in ipairs(M.floors) do if y >= f[2] - 1 then best = f[1] end end
  return best
end

function M.known(name)
  for _, f in ipairs(M.floors) do if f[1] == name then return true end end
  return false
end

function M.fetch(url)
  if not http then return nil, "http is off on this server" end
  local h, err = http.get(url .. "?t=" .. os.epoch("utc"))
  if not h then return nil, err end
  local body = h.readAll(); h.close()
  return body
end

-- the floor: GPS guess, confirmed (or replaced) by whoever is at the keyboard
function M.askFloor(read_, locate)
  local guess
  local ok, _, y = pcall(locate or gps.locate, 3)
  if ok and y then guess = M.floorAt(math.floor(y)) end
  while true do
    if guess then write("Floor " .. guess .. "? Enter = yes, or type the floor: ")
    else write("Which floor is this? (L1 L2 P3 P2 P1 G 2 3 4 5 6): ") end
    local a = ((read_ or read)() or ""):match("^%s*(%S*)"):upper()
    if a == "" and guess then return guess end
    if M.known(a) then return a end
    print("Not a floor: " .. a)
  end
end

function M.install(role, read_, locate)
  role = role or "hall"
  pcall(function() peripheral.find("modem", function(n) if not rednet.isOpen(n) then rednet.open(n) end return true end) end)
  if role == "gps" then
    -- a GPS host has to announce exactly where it is: ask the GPS that's running now and keep that for good,
    -- so the old hosts can go once four of these are up
    local ok, x, y, z = pcall(locate or gps.locate, 5)
    if not ok or not x then return false, "no GPS answer: leave the old GPS computers running until this one's set up" end
    x, y, z = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
    local f = fs.open("/startup.lua", "w")
    f.writeLine(("shell.run(\"gps\", \"host\", %d, %d, %d)"):format(x, y, z))
    f.close()
    pcall(os.setComputerLabel, "gps")
    return true, ("gps at %d %d %d"):format(x, y, z)
  end
  local floor
  if role == "hall" or role == "landing" then
    floor = M.askFloor(read_, locate)
    local f = fs.open("/floor.txt", "w"); f.writeLine(floor); f.close()
    -- a hall station serves both lifts, so it must not be tied to one car
    if role == "hall" and fs.exists("/car.txt") then fs.delete("/car.txt") end
  end
  local body, err = M.fetch(M.base .. "update/update.lua")
  if not body then return false, "couldn't download the updater: " .. tostring(err) end
  local f = fs.open("/update.lua", "w"); f.write(body); f.close()
  local update = dofile("/update.lua")
  update.base = M.base
  local todo, why = update.check(role)
  if not todo then return false, why end
  local ok, e = update.apply(todo)
  if not ok then return false, e end
  pcall(os.setComputerLabel, role .. (floor and (" " .. floor) or ""))
  return true, floor
end

if select("#", ...) > 0 and (...) == "install" then return M end
local role = ...
print("Elevator setup: " .. (role or "hall"))
local ok, info = M.install(role)
if not ok then print("Failed: " .. tostring(info)) return end
print("Installed" .. (info and (role == "gps" and (": " .. info) or (" for floor " .. info)) or "") .. ", rebooting")
sleep(1)
os.reboot()
