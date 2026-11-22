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
  for _, p in ipairs({ "/.versions", "/landing.lua", "/startup.lua", "/update.lua", "/update.log" }) do
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
