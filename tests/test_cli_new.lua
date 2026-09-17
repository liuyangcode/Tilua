if not ngx then
    _G.ngx = { now = os.time }
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

local CLI = require("Tilua.cli")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed", 2) end
end

local function capture_print(fn)
    local buf = {}
    local real = print
    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        buf[#buf + 1] = table.concat(parts, "\t")
    end
    local ok, rc = pcall(fn)
    _G.print = real
    if not ok then error(rc, 2) end
    return rc, table.concat(buf, "\n")
end

local function read(p)
    local f = io.open(p, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-----------------------------------------------------------------------
-- scaffold generation
-----------------------------------------------------------------------

local dir = os.tmpname() .. "_tilua_new"
os.remove(dir)

local rc = capture_print(function()
    return CLI.new_project(nil, { "MyApp", "--dir", dir })
end)
assert_true(rc == 0, "tilua new should succeed into a fresh directory")

for _, rel in ipairs({
    "MyApp/app.lua", "MyApp/routes.lua", "MyApp/config/dev.lua",
    "MyApp/controller/index.lua", "MyApp/view/index.html",
    "public/.gitkeep", ".gitignore", "README.md",
}) do
    assert_true(read(dir .. "/" .. rel) ~= nil, "scaffold should create " .. rel)
end

-----------------------------------------------------------------------
-- generated Lua must be syntactically valid AND use current APIs
-----------------------------------------------------------------------

local loader = loadstring or load
for _, rel in ipairs({
    "MyApp/app.lua", "MyApp/routes.lua",
    "MyApp/config/dev.lua", "MyApp/controller/index.lua",
}) do
    local src = read(dir .. "/" .. rel)
    local chunk, err = loader(src, "=" .. rel)
    assert_true(chunk ~= nil, rel .. " is not valid Lua: " .. tostring(err))
end

local app_src = read(dir .. "/MyApp/app.lua")
-- `derive()` does not exist in the framework; scaffolding it would produce a
-- project that fails on the first request.
assert_true(app_src:find("Tilua.app\").define()", 1, true),
    "app.lua must use Tilua.app.define()")
assert_true(not app_src:find("derive(", 1, true),
    "app.lua must not use the non-existent derive()")
assert_true(app_src:find('App.name   = "MyApp"', 1, true),
    "app.lua must set the app name to match the module path")

local routes_src = read(dir .. "/MyApp/routes.lua")
assert_true(routes_src:find("Tilua.http.router", 1, true), "routes.lua should require Tilua.http.router")
assert_true(routes_src:find("Tilua.http.response", 1, true), "routes.lua should require Tilua.http.response")

-----------------------------------------------------------------------
-- generated routes really register against the live router
-----------------------------------------------------------------------

package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path
local router = require("Tilua.http.router")
router.set_app_name("MyApp")
require("MyApp.routes")

local rules = router.rules["MyApp"] or {}
local count = 0
for _ in pairs(rules) do count = count + 1 end
assert_true(count == 3, "scaffolded routes.lua should register 3 routes, got " .. count)

-----------------------------------------------------------------------
-- generated view renders through Tilua.template
-----------------------------------------------------------------------

local engine = require("Tilua.template").new({ root = dir .. "/MyApp/view" })
local html = engine:render("index.html", { app_name = "MyApp", message = "hi" })
assert_true(html:find("<h1>MyApp</h1>", 1, true), "view should interpolate app_name")
assert_true(html:find("hi", 1, true), "view should interpolate message")

-----------------------------------------------------------------------
-- the scaffolded config lines up with what `tilua serve` declares
-----------------------------------------------------------------------

local cfg_src = read(dir .. "/MyApp/config/dev.lua")
local shdict = cfg_src:match('SHDICIT_NAME%s*=%s*"([%w_]+)"')
assert_true(shdict ~= nil, "config should set SHDICIT_NAME")

local _, conf = capture_print(function()
    return CLI.serve(nil, { "--root", dir, "--print-conf" })
end)
assert_true(conf:find("lua_shared_dict " .. shdict, 1, true),
    "serve must declare the shared dict the scaffold configures (" .. shdict .. ")")
assert_true(conf:find('require("MyApp.app")', 1, true),
    "serve should autodetect the scaffolded app")

-----------------------------------------------------------------------
-- guard rails
-----------------------------------------------------------------------

assert_true(capture_print(function() return CLI.new_project(nil, {}) end) == 1,
    "missing name should fail")
assert_true(capture_print(function() return CLI.new_project(nil, { "my-app" }) end) == 1,
    "invalid module name should be rejected")
assert_true(capture_print(function() return CLI.new_project(nil, { "9lives" }) end) == 1,
    "module name starting with a digit should be rejected")
assert_true(capture_print(function()
    return CLI.new_project(nil, { "MyApp", "--dir", dir })
end) == 1, "a non-empty target directory should be refused without --force")

-- --force fills gaps but must never clobber existing files
local before = read(dir .. "/MyApp/app.lua")
assert_true(capture_print(function()
    return CLI.new_project(nil, { "MyApp", "--dir", dir, "--force" })
end) == 0, "--force should succeed")
assert_true(read(dir .. "/MyApp/app.lua") == before, "--force must not overwrite existing files")

os.execute("rm -rf '" .. dir .. "'")

print("test_cli_new: OK")
