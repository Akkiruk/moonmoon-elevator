-- Run from this folder: craftos-mcp test
-- The installer against a fake server (url -> body) and a fake GPS and keyboard.
local install = require "install"

local function read(p) local f = fs.open(p, "r"); local s = f.readAll(); f.close(); return s end
local realUpdater = read("/update.lua")

local served
local function serve(files)
  served = files
  install.base = "https://x/"
  _G.http = {
    get = function(req)
      local url = (type(req) == "table" and req.url or req):gsub("%?.*$", "")
      local body = served[url:sub(#"https://x/" + 1)]
      if not body then return nil, "404" end
      return { readAll = function() return body end, close = function() end }
    end,
  }
end

local function server()
  serve({
    ["update/update.lua"] = realUpdater,
    ["manifest.json"] = textutils.serialiseJSON({ roles = { hall = {
      ["startup.lua"] = { src = "hall/startup.lua", sha = "s1" },
      ["landing.lua"] = { src = "landing/landing.lua", sha = "l1" },
    } } }),
    ["hall/startup.lua"] = "-- hall startup",
    ["landing/landing.lua"] = "-- landing",
  })
end

local function keys(list) local i = 0; return function() i = i + 1; return list[i] end end
local function at(y) return function() return 40, y, -10 end end
local function noGps() return nil end

local function clean()
  for _, p in ipairs({ "/.versions", "/landing.lua", "/startup.lua", "/floor.txt", "/car.txt", "/update.log" }) do
    if fs.exists(p) then fs.delete(p) end
  end
  os.setComputerLabel(nil)
end

ccunit.test("floor from height: the landing level or just above it", function()
  ccunit.eq(install.floorAt(65), "L1")
  ccunit.eq(install.floorAt(70), "L1")
  ccunit.eq(install.floorAt(71), "L2")
  ccunit.eq(install.floorAt(104), "G")
  ccunit.eq(install.floorAt(107), "G")
  ccunit.eq(install.floorAt(108), "2")
  ccunit.eq(install.floorAt(126), "6")
end, { timeout = 10 })

ccunit.test("hall install: GPS floor, Enter accepts, files in, labelled, no car", function()
  clean()
  server()
  local f = fs.open("/car.txt", "w"); f.writeLine("A"); f.close()
  local ok, floor = install.install(nil, keys({ "" }), at(106))
  ccunit.truthy(ok, tostring(floor))
  ccunit.eq(floor, "G")
  ccunit.eq(read("/floor.txt"), "G\n")
  ccunit.eq(read("/startup.lua"), "-- hall startup")
  ccunit.eq(read("/landing.lua"), "-- landing")
  ccunit.eq(fs.exists("/car.txt"), false, "a hall station isn't tied to a car")
  ccunit.eq(os.getComputerLabel(), "hall G")
end, { timeout = 10 })

ccunit.test("no GPS: asks, and turns away what isn't a floor", function()
  clean()
  server()
  local ok, floor = install.install("hall", keys({ "7", "p2" }), noGps)
  ccunit.truthy(ok)
  ccunit.eq(floor, "P2")
  ccunit.eq(read("/floor.txt"), "P2\n")
end, { timeout = 10 })

ccunit.test("typing a floor overrides the GPS guess", function()
  clean()
  server()
  local _, floor = install.install("hall", keys({ "3" }), at(110))
  ccunit.eq(floor, "3")
end, { timeout = 10 })

ccunit.test("no http: a clear failure, nothing installed", function()
  clean()
  _G.http = nil
  local ok, why = install.install("hall", keys({ "" }), at(106))
  ccunit.eq(ok, false)
  ccunit.contains(why, "http")
  ccunit.eq(fs.exists("/startup.lua"), false)
end, { timeout = 10 })

ccunit.test("gps host: takes its exact spot from the running GPS and hosts it from then on", function()
  clean()
  local ok, info = install.install("gps", nil, function() return 30.0, 44.99, -12.0 end)
  ccunit.truthy(ok, tostring(info))
  ccunit.contains(read("/startup.lua"), 'shell.run("gps", "host", 30, 45, -12)')
  ccunit.eq(os.getComputerLabel(), "gps")
  ccunit.eq(load(read("/startup.lua")) ~= nil, true, "the startup compiles")
end, { timeout = 10 })

ccunit.test("gps host with no GPS answering: refuses, writes nothing", function()
  clean()
  local ok, why = install.install("gps", nil, function() return nil end)
  ccunit.eq(ok, false)
  ccunit.contains(why, "old GPS")
  ccunit.eq(fs.exists("/startup.lua"), false)
end, { timeout = 10 })
