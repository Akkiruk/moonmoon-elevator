-- Run from this folder: craftos-mcp test
-- http is replaced by a fake server: a table of url -> body, answered through the real http events.
local update = require "update"

local served, asked
local function serve(files)
  served, asked = files, {}
  update.base = "https://x/"
  _G.http = {
    get = function(req)
      local url = req.url:gsub("%?.*$", "")
      asked[#asked + 1] = url
      local body = served[url:sub(#"https://x/" + 1)]
      if not body then return nil, "404" end
      return { readAll = function() return body end, close = function() end }
    end,
  }
end

local function manifest(files)
  return textutils.serialiseJSON({ roles = { landing = files } })
end

local function read(p) local f = fs.open(p, "r"); local s = f.readAll(); f.close(); return s end

local function clean()
  for _, p in ipairs({ "/.versions", "/landing.lua", "/startup.lua", "/update.log" }) do
    if fs.exists(p) then fs.delete(p) end
  end
end

ccunit.test("installs what changed, then nothing until the sha moves", function()
  clean()
  serve({
    ["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a1" } }),
    ["landing/landing.lua"] = "print('v1')",
  })
  ccunit.truthy(update.run("landing"), "first run installs")
  ccunit.eq(read("/landing.lua"), "print('v1')")
  ccunit.eq(update.run("landing"), false, "same sha: nothing to do")
  served["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a2" } })
  served["landing/landing.lua"] = "print('v2')"
  ccunit.truthy(update.run("landing"), "new sha installs")
  ccunit.eq(read("/landing.lua"), "print('v2')")
end, { timeout = 10 })

ccunit.test("a failed download leaves the old files and the old versions alone", function()
  clean()
  serve({
    ["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a1" } }),
    ["landing/landing.lua"] = "print('v1')",
  })
  update.run("landing")
  served["manifest.json"] = manifest({
    ["landing.lua"] = { src = "landing/landing.lua", sha = "a2" },
    ["startup.lua"] = { src = "landing/startup.lua", sha = "s2" }, -- missing on the server
  })
  served["landing/landing.lua"] = "print('v2')"
  ccunit.eq(update.run("landing"), false)
  ccunit.eq(read("/landing.lua"), "print('v1')", "nothing half-installed")
  ccunit.truthy(read("/update.log"):find("download failed"), "logged")
end, { timeout = 10 })

ccunit.test("no server or no http: just keeps going", function()
  clean()
  serve({})
  ccunit.eq(update.run("landing"), false)
  _G.http = nil
  ccunit.eq(update.run("landing"), false)
end, { timeout = 10 })

ccunit.test("a slow server times out instead of hanging the boot", function()
  clean()
  update.timeout = 0.5
  local gotTimeout
  _G.http = { get = function(req) gotTimeout = req.timeout; sleep(req.timeout); return nil, "Timed out" end }
  local t0 = os.clock()
  ccunit.eq(update.run("landing"), false)
  ccunit.eq(gotTimeout, 0.5, "the request carries our timeout")
  ccunit.truthy(os.clock() - t0 < 2, "gave up in time")
  update.timeout = 4
end, { timeout = 10 })

ccunit.test("files the manifest doesn't list are never touched", function()
  clean()
  local f = fs.open("/floor.txt", "w"); f.write("G"); f.close()
  serve({
    ["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a1" } }),
    ["landing/landing.lua"] = "x",
  })
  update.run("landing")
  ccunit.eq(read("/floor.txt"), "G")
  fs.delete("/floor.txt")
end, { timeout = 10 })

ccunit.test("update music pulls a track folder from any url", function()
  serve({
    ["song/list.txt"] = "01.ogg 0 100\n02.ogg 0 100\n",
    ["song/01.ogg"] = "AAAA", ["song/02.ogg"] = "BBBB",
  })
  local ok, why = update.music("https://x/song", "/tmp_tracks")
  ccunit.truthy(ok, why)
  ccunit.eq(read("/tmp_tracks/02.ogg"), "BBBB")
  ccunit.truthy(read("/tmp_tracks/list.txt"):find("01.ogg"))
  update.timeout = 4
  served["song/02.ogg"] = nil
  ccunit.eq(update.music("https://x/song/", "/tmp_tracks"), false, "a missing part fails")
  fs.delete("/tmp_tracks")
end, { timeout = 10 })

ccunit.test("a startup restarts a program that crashes and checks for a fix each time", function()
  clean()
  serve({})
  -- a stand-in program that counts its runs and then crashes
  local f = fs.open("/landing.lua", "w")
  f.write("local n = settings.get('t.runs') or 0 settings.set('t.runs', n + 1) error('boom')")
  f.close()
  settings.unset("t.runs")
  local src = fs.open("/startup_under_test.lua", "w")
  src.write(read("/landing_startup.lua"))
  src.close()
  parallel.waitForAny(function() shell.run("/startup_under_test.lua") end, function() sleep(11) end)
  ccunit.truthy((settings.get("t.runs") or 0) >= 2, "ran " .. tostring(settings.get("t.runs")) .. " times")
  local checks = 0
  for _, u in ipairs(asked) do if u:find("manifest.json") then checks = checks + 1 end end
  ccunit.truthy(checks >= 2, "asked for a fix after the crash (" .. checks .. " checks)")
  settings.unset("t.runs")
  fs.delete("/startup_under_test.lua")
end, { timeout = 20 })

ccunit.test("Lua that doesn't compile is refused and the old file stays", function()
  clean()
  serve({
    ["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a1" } }),
    ["landing/landing.lua"] = "print('ok')",
  })
  update.run("landing")
  served["manifest.json"] = manifest({ ["landing.lua"] = { src = "landing/landing.lua", sha = "a2" } })
  served["landing/landing.lua"] = "print('oops'"
  ccunit.eq(update.run("landing"), false)
  ccunit.eq(read("/landing.lua"), "print('ok')")
  ccunit.truthy(read("/update.log"):find("doesn't compile"), "logged why")
end, { timeout = 10 })

ccunit.test("a new updater keeps the old one as update.prev.lua, and either loads with dofile", function()
  clean()
  if fs.exists("/update.prev.lua") then fs.delete("/update.prev.lua") end
  local real = read("/update.lua")
  local f = fs.open("/update.lua", "w"); f.write("local M = { old = true } return M"); f.close()
  serve({
    ["manifest.json"] = manifest({ ["update.lua"] = { src = "update/update.lua", sha = "u2" } }),
    ["update/update.lua"] = "local M = { new = true } if select('#', ...) == 0 or (...) == 'update' then return M end",
  })
  ccunit.truthy(update.run("landing"))
  ccunit.truthy(dofile("/update.prev.lua").old, "the previous updater is kept")
  ccunit.truthy(dofile("/update.lua").new, "the new one loads as a module through dofile")
  fs.delete("/update.prev.lua")
  f = fs.open("/update.lua", "w"); f.write(real); f.close()
end, { timeout = 10 })
