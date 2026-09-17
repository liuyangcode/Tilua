if not ngx then
    _G.ngx = { now = os.time }
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

local CLI = require("Tilua.cli")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed", 2) end
end

-----------------------------------------------------------------------
-- fixture project: <root>/MyApp/app.lua
-----------------------------------------------------------------------

local root = os.tmpname() .. "_tilua_serve"
os.execute("mkdir -p '" .. root .. "/MyApp'")
local f = assert(io.open(root .. "/MyApp/app.lua", "w"))
f:write("return {}\n")
f:close()

--- Run a command while capturing everything it prints.
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

-----------------------------------------------------------------------
-- app autodetection + conf generation
-----------------------------------------------------------------------

local rc, out = capture_print(function()
    return CLI.serve(nil, { "--root", root, "--print-conf", "--port", "9090" })
end)

assert_true(rc == 0, "serve --print-conf should succeed")
assert_true(out:find("MyApp.app", 1, true), "should autodetect the MyApp module")
assert_true(out:find("listen 9090;", 1, true), "--port should be honoured")
assert_true(out:find("lua_code_cache off;", 1, true), "dev conf must disable the Lua code cache")
assert_true(out:find("daemon off;", 1, true), "dev conf must run in the foreground")

for _, phase in ipairs({ "init_by_lua_block", "init_worker_by_lua_block",
                        "rewrite_by_lua_block", "access_by_lua_block",
                        "content_by_lua_block", "log_by_lua_block" }) do
    assert_true(out:find(phase, 1, true), "conf should wire " .. phase)
end

-- braces must balance, or nginx will refuse to start
local depth = 0
for ch in out:gmatch("[{}]") do
    depth = depth + (ch == "{" and 1 or -1)
    assert_true(depth >= 0, "unbalanced braces in generated conf")
end
assert_true(depth == 0, "unbalanced braces in generated conf")

-- the conf is also written to disk, not only printed
local cf = io.open(root .. "/.tilua/dev.nginx.conf", "r")
assert_true(cf ~= nil, "serve should write .tilua/dev.nginx.conf")
cf:close()

-----------------------------------------------------------------------
-- flag styles: --flag=value must behave like --flag value
-----------------------------------------------------------------------

local rc2, out2 = capture_print(function()
    return CLI.serve(nil, { "--root=" .. root, "--app=MyApp", "--print-conf", "--port=7000" })
end)
assert_true(rc2 == 0, "--flag=value form should work")
assert_true(out2:find("listen 7000;", 1, true), "--port=N should be honoured")

-----------------------------------------------------------------------
-- error paths
-----------------------------------------------------------------------

local rc3 = capture_print(function()
    return CLI.serve(nil, { "--root", root, "--app", "Nope", "--print-conf" })
end)
assert_true(rc3 == 1, "unknown --app should fail")

local empty = os.tmpname() .. "_tilua_serve_empty"
os.execute("mkdir -p '" .. empty .. "/notanapp'")
local rc4 = capture_print(function()
    return CLI.serve(nil, { "--root", empty, "--print-conf" })
end)
assert_true(rc4 == 1, "a project with no <Name>/app.lua should fail")

local multi = os.tmpname() .. "_tilua_serve_multi"
os.execute("mkdir -p '" .. multi .. "/AppA' '" .. multi .. "/AppB'")
for _, n in ipairs({ "AppA", "AppB" }) do
    local h = assert(io.open(multi .. "/" .. n .. "/app.lua", "w"))
    h:write("return {}\n"); h:close()
end
local rc5, out5 = capture_print(function()
    return CLI.serve(nil, { "--root", multi, "--print-conf" })
end)
assert_true(rc5 == 1, "ambiguous autodetection should fail")
assert_true(out5:find("--app", 1, true), "ambiguity error should tell the user to pass --app")

os.execute("rm -rf '" .. root .. "' '" .. empty .. "' '" .. multi .. "'")

print("test_cli_serve: OK")
