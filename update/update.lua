-- Self-updater shared by every elevator computer. It reads manifest.json from the public repo, and any file
-- whose sha differs from the one it last installed gets downloaded again. Local files (floor.txt, car.txt,
-- .settings, the music) are never in the manifest, so they're never touched.
--
--   update <role>          check now, install what changed and reboot if anything did
--   update music <url>     download a music track folder (list.txt plus its parts) from your own web space
--                          into /tracks/sins; the song isn't in the public repo
--   update.boot(role)      the same at startup, but a failure never stops the program from starting
--   update.watch(role)     background loop: checks every so often and reboots once the computer is idle
--
-- A program marks itself busy with _G.mmliftBusy = true (the hub while a car moves or a brake is off, the cab
-- while its car moves); the reboot waits for that to clear.

local M = {
  base = "https://raw.githubusercontent.com/Akkiruk/moonmoon-elevator/main/",
  every = 600,    -- seconds between checks
  timeout = 4,    -- per request; a slow download at boot only delays the start this long
  stateFile = "/.versions",
}

local function readJson(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close()
  return textutils.unserialiseJSON(s)
end

local function writeJson(path, t)
  local f = fs.open(path, "w"); f.write(textutils.serialiseJSON(t)); f.close()
end

-- Returns the body or nil, why. The timeout keeps a slow server from holding up the boot.
function M.fetch(url)
  if not http then return nil, "http is off" end
  local h, err, eh = http.get({ url = url .. "?t=" .. os.epoch("utc"), binary = true, timeout = M.timeout })
  if not h then
    if eh then eh.close() end
    return nil, err
  end
  local body = h.readAll()
  h.close()
  return body
end

-- What would change: a list of { name, src, sha }, or nil, why.
function M.check(role)
  local body, err = M.fetch(M.base .. "manifest.json")
  if not body then return nil, err end
  local man = textutils.unserialiseJSON(body)
  local files = man and man.roles and man.roles[role]
  if not files then return nil, "no role " .. tostring(role) .. " in the manifest" end
  local have = readJson(M.stateFile) or {}
  local todo = {}
  for name, f in pairs(files) do
    if have[name] ~= f.sha or not fs.exists("/" .. name) then todo[#todo + 1] = { name = name, src = f.src, sha = f.sha } end
  end
  table.sort(todo, function(a, b) return a.name < b.name end)
  return todo
end

-- Download everything first and only then write, so a dropped connection can't leave half an update.
function M.apply(todo)
  local got = {}
  for _, f in ipairs(todo) do
    local body, err = M.fetch(M.base .. f.src)
    if not body then return false, f.src .. ": " .. tostring(err) end
    -- a typo in a push must never reach the disk: Lua that doesn't compile is refused and the old file stays
    if f.name:match("%.lua$") then
      local fn, why = load(body, "=" .. f.name)
      if not fn then return false, f.src .. " doesn't compile: " .. tostring(why) end
    end
    got[#got + 1] = { f = f, body = body }
  end
  local have = readJson(M.stateFile) or {}
  for _, g in ipairs(got) do
    -- keep the updater that works now, so a startup can fall back to it if the new one breaks at run time
    if g.f.name == "update.lua" and fs.exists("/update.lua") then
      if fs.exists("/update.prev.lua") then fs.delete("/update.prev.lua") end
      fs.copy("/update.lua", "/update.prev.lua")
    end
    local h = fs.open("/" .. g.f.name .. ".new", "wb"); h.write(g.body); h.close()
    if fs.exists("/" .. g.f.name) then fs.delete("/" .. g.f.name) end
    fs.move("/" .. g.f.name .. ".new", "/" .. g.f.name)
    have[g.f.name] = g.f.sha
  end
  writeJson(M.stateFile, have)
  return true
end

local function log(msg)
  local f = fs.open("/update.log", fs.exists("/update.log") and fs.getSize("/update.log") < 4000 and "a" or "w")
  f.writeLine(os.date("!%Y-%m-%d %H:%M") .. " " .. msg); f.close()
end

-- Returns true when it installed something (the caller reboots).
function M.run(role)
  local todo, err = M.check(role)
  if not todo then log("check failed: " .. tostring(err)); return false end
  if #todo == 0 then return false end
  local names = {}
  for i, f in ipairs(todo) do names[i] = f.name end
  local ok, why = M.apply(todo)
  if not ok then log("download failed: " .. why); return false end
  log("updated " .. table.concat(names, ", "))
  return true
end

function M.boot(role)
  local ok, changed = pcall(M.run, role)
  if ok and changed then os.reboot() end
end

function M.watch(role)
  sleep(30 + (os.getComputerID() % 60) * 5) -- spread the checks so forty computers don't ask at once
  while true do
    local ok, changed = pcall(M.run, role)
    if ok and changed then
      while _G.mmliftBusy do sleep(2) end
      os.reboot()
    end
    sleep(M.every)
  end
end

-- Fetch a track folder made by tools/to-ogg.mjs: <url>/list.txt, then each part it names. Parts are written one
-- at a time over the old ones, because the cab's disk can't hold two copies of the song.
function M.music(url, dir)
  url = url:gsub("/*$", "/")
  dir = dir or "/tracks/sins"
  local list, err = M.fetch(url .. "list.txt")
  if not list then return false, "list.txt: " .. tostring(err) end
  local names = {}
  for line in list:gmatch("[^\r\n]+") do
    local name = line:match("^(%S+)")
    if name then names[#names + 1] = name end
  end
  if #names == 0 then return false, "list.txt names no parts" end
  fs.makeDir(dir)
  for i, name in ipairs(names) do
    M.timeout = 30 -- a part is around 60 KB
    local body, why = M.fetch(url .. name)
    if not body then return false, name .. ": " .. tostring(why) end
    local h = fs.open(dir .. "/" .. name, "wb"); h.write(body); h.close()
    print(("  %d/%d %s"):format(i, #names, name))
  end
  local h = fs.open(dir .. "/list.txt", "w"); h.write(list); h.close()
  return true
end

-- require "update" passes "update"; dofile passes nothing. Either way it's the module, not the command.
if select("#", ...) == 0 or (...) == "update" then return M end
if (...) == "music" then
  local url = select(2, ...)
  if not url then print("usage: update music <url of the folder holding list.txt>") return end
  local ok, why = M.music(url)
  print(ok and "music installed, reboot the cab to play it" or ("failed: " .. why))
  return
end
local role = ...
if not role then
  local f = fs.exists("/role.txt") and fs.open("/role.txt", "r")
  if f then role = (f.readLine() or ""):match("%S+"); f.close() end
end
if not role then print("usage: update <role>  (or put the role in /role.txt)") return end
print("checking " .. role .. " ...")
local todo, err = M.check(role)
if not todo then print("failed: " .. tostring(err)) return end
if #todo == 0 then print("up to date") return end
for _, f in ipairs(todo) do print("  " .. f.name) end
local ok, why = M.apply(todo)
if not ok then print("failed: " .. why) return end
print("done, rebooting")
sleep(1)
os.reboot()
