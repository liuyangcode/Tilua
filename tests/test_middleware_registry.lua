--- Every middleware named by the framework's DEFAULT config must load.
---
--- `Tilua/config/default.lua` wires the `api` and `web` middleware groups to
--- names like `json`, which resolve to `Tilua.middleware.json_response`.  That
--- module required `Tilua.midware.base` — a path that does not exist (only the
--- `Tilua.midware` *module* shim does, not the `.base` submodule) — so any app
--- using the default groups crashed at boot with
---     module 'Tilua.midware.base' not found
--- while the test suites stayed green, because nothing loaded that module.
---
--- Run: luajit tests/support/lua_stub.lua tests/test_middleware_registry.lua

package.path = "./tests/fixtures/?.lua;./tests/fixtures/?/init.lua;"
            .. "./?.lua;./?/init.lua;" .. (package.path or "")

local failures, checks = 0, 0

local function ok(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. "\n")
    end
end

local function eq(actual, expected, label)
    checks = checks + 1
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write(string.format("FAIL: %s\n  expected: %s\n  actual:   %s\n",
            label, tostring(expected), tostring(actual)))
    end
end

----------------------------------------------------------------------
-- Shared fake request context.
--
-- Middleware constructors do real work with the context: `body_parser` reads
-- `ctx.config.multipart` at construction time, and `session` reads
-- `ctx.logger`.  A bare `{}` therefore fails for legitimate reasons unrelated to
-- the bug under test, so provide the shape they actually require.
----------------------------------------------------------------------
local function fake_ctx()
    return {
        name = "TestApp",
        logger = {
            debug = function() end,
            info  = function() end,
            error = function() end,
            warn  = function() end,
            write = function() end,
        },
        config = {
            multipart = {
                tmpdir          = "/tmp",
                chunk_size      = 4096,
                file_size       = 1048576,
                whitelist       = { ".txt" },
                file_extensions = { ".txt" },
            },
        },
    }
end

----------------------------------------------------------------------
-- 1. every alias in the default config resolves to a loadable module
----------------------------------------------------------------------
do
    local default = require("Tilua.config.default")

    local aliases = default.middleware_alias or default.midware_alias or {}
    local names = {}
    for _, v in pairs(aliases) do
        names[#names + 1] = v
    end
    table.sort(names)

    ok(#names > 0, "default config declares middleware aliases")

    for _, mod in ipairs(names) do
        local ok_load, loaded = pcall(require, mod)
        ok(ok_load, "require('" .. mod .. "') works")
        if ok_load then
            local t = type(loaded)
            ok(t == "table" or t == "function",
                mod .. " is a table or function (got " .. t .. ")")

            if t == "table" then
                local instantiable = type(loaded.define) == "function"
                    or type(loaded._construct) == "function"
                    or type(loaded.new) == "function"
                    or type(getmetatable(loaded).__call) == "function"
                ok(instantiable, mod .. " is instantiable")
            end

            -- Instantiating must work for every one of them.  This is what
            -- actually caught the broken base path: the require itself died.
            local ok_inst, inst = pcall(function()
                if type(loaded.define) == "function" then
                    return loaded.define()(fake_ctx(), {})
                end
                return loaded(fake_ctx(), {})
            end)
            ok(ok_inst, mod .. " can be constructed"
                .. (ok_inst and "" or (" (" .. tostring(inst) .. ")")))
            if ok_inst and type(inst) == "table" then
                ok(type(inst.handle) == "function",
                    mod .. " instance exposes handle()")
            end
        end
    end
end

----------------------------------------------------------------------
-- 2. every group in the default config expands to loadable middleware
----------------------------------------------------------------------
do
    local mw = require("Tilua.middleware")
    local default = require("Tilua.config.default")

    mw.load(default)

    for _, group in ipairs({ "api", "web" }) do
        local entries = mw.get_group(group)
        ok(type(entries) == "table" and #entries > 0,
            "group '" .. group .. "' expands to entries")

        for _, entry in ipairs(entries) do
            local name = type(entry) == "table" and entry[1] or entry
            ok(type(name) == "string",
                "group '" .. group .. "' entry has a string name")

            -- Resolve through the same code path the request pipeline uses.
            local manager = mw({ name = "TestApp" })
            local ok_res, inst = pcall(function()
                return manager:instance({ name }, fake_ctx())
            end)
            ok(ok_res, "group '" .. group .. "' -> '" .. tostring(name)
                .. "' resolves"
                .. (ok_res and "" or (" (" .. tostring(inst) .. ")")))
        end
    end
end

----------------------------------------------------------------------
-- 3. every file under Tilua/middleware/ is loadable
----------------------------------------------------------------------
do
    -- Catches the same class of bug for middleware not referenced by config.
    local p = io.popen("find Tilua/middleware -maxdepth 1 -name '*.lua' 2>/dev/null")
    local mods = {}
    if p then
        for file in p:lines() do
            local mod = file:gsub("%.lua$", ""):gsub("/", ".")
            if mod:sub(-5) ~= ".init" then
                mods[#mods + 1] = mod
            end
        end
        p:close()
    end

    ok(#mods > 0, "found middleware modules to check")

    for _, mod in ipairs(mods) do
        local ok_load, err = pcall(require, mod)
        ok(ok_load, "require('" .. mod .. "') works"
            .. (ok_load and "" or (" -- " .. tostring(err):gsub("\n.*", ""))))
    end
end

----------------------------------------------------------------------
print(string.format("middleware-registry tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("middleware-registry tests passed")
