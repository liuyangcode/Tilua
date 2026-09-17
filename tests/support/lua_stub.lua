--- Shared no-OpenResty test harness.
---
--- Provides the minimal `ngx` and `lfs` surface that Tilua modules touch at
--- *load* time, so container/lifecycle wiring can be exercised under plain
--- LuaJIT (and under `resty`, where the real ngx table already exists and is
--- left untouched).
---
--- Usage:
---   luajit tests/support/lua_stub.lua tests/test_app_container.lua
---   luajit tests/support/lua_stub.lua tests/test_container.lua

package.path = "./tests/fixtures/?.lua;./tests/fixtures/?/init.lua;"
            .. "./?.lua;./?/init.lua;" .. (package.path or "")

-----------------------------------------------------------------------
-- Locate OpenResty's lualib (cjson etc.).  The base LuaJIT image ships the
-- shared libraries but does not put them on the default search path, so
-- `resty` is not required as long as we can find the directory.
-----------------------------------------------------------------------
local function add_lualib(dir)
    local probe = dir .. "/cjson.so"
    local f = io.open(probe, "rb")
    if not f then
        return false
    end
    f:close()
    package.path = package.path .. ";" .. dir .. "/?.lua;" .. dir .. "/?/init.lua"
    package.cpath = package.cpath .. ";" .. dir .. "/?.so"
    return true
end

local lualib_candidates = {
    "/usr/local/openresty/lualib",
    "/usr/local/openresty/lualib/resty",
}
local found_lualib = false
for _, dir in ipairs(lualib_candidates) do
    if add_lualib(dir) then
        found_lualib = true
    end
end
if not found_lualib then
    -- also try the directory of the running interpreter
    local ok_ffi = pcall(require, "ffi")
    if ok_ffi then
        io.stderr:write("warn: openresty lualib not found; cjson-dependent modules will fail\n")
    end
end

local target = arg and arg[1]
if not target or target == "" then
    io.stderr:write("usage: luajit tests/support/lua_stub.lua <test-file.lua>\n")
    os.exit(2)
end

-----------------------------------------------------------------------
-- ngx (only when running outside OpenResty)
-----------------------------------------------------------------------
if not rawget(_G, "ngx") then
    local function noop() end
    local function empty_table()
        return {}
    end

    local ngx_re = {
        -- Enough for load-time capture and non-regex code paths.
        match = function() return nil end,
        find  = function() return nil end,
        sub   = function(s) return s end,
        gsub  = function(s) return s end,
    }

    local ngx = {
        -- constants used by logging
        STDERR = "STDERR", EMERG = "EMERG", ALERT = "ALERT", CRIT = "CRIT",
        ERR = "ERR", WARN = "WARN", NOTICE = "NOTICE", INFO = "INFO",
        DEBUG = "DEBUG", NONE = "NONE",

        -- time / ids
        now = function() return 1700000000 end,
        time = function() return 1700000000 end,
        update_time = noop,
        localtime = function() return "2026-01-01 00:00:00" end,
        cookie_time = function() return "Wed, 01-Jan-2026 00:00:00 GMT" end,
        utctime = function() return "2026-01-01" end,
        today = function() return "2026-01-01" end,

        -- encoding / hashing
        md5 = function(s) return "md5:" .. tostring(s) end,
        encode_base64 = function(s) return tostring(s) end,
        decode_base64 = function(s) return tostring(s) end,
        escape_uri = function(s) return tostring(s) end,
        unescape_uri = function(s) return tostring(s) end,
        quote_sql_str = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end,

        -- logging
        log = noop,
        print = function(...) io.write(...) end,
        say = function(...) io.write(table.concat({ ... }, "\t"), "\n") end,
        exit = function(code) os.exit(code or 0) end,
        flush = noop,
        sleep = noop,

        re = ngx_re,
        worker = {
            pid = function() return 4242 end,
            id = function() return 0 end,
            count = function() return 1 end,
        },
        config = { subsystem = "http", nginx_version = 1021004 },
        -- A real table: the framework writes ngx.var (e.g. nothing, but tests
        -- and middleware set uri/request_method), and a noop __newindex would
        -- silently swallow those writes and change observed behaviour.
        var = {},
        ctx = {},
        header = {},
        status = 200,
        headers_sent = false,
        req = {
            get_headers = empty_table,
            get_uri_args = empty_table,
            get_post_args = empty_table,
            read_body = noop,
            get_body_data = function() return nil end,
            get_body_file = function() return nil end,
            set_header = noop,
            start_time = function() return 1700000000 end,
        },
        resp = {
            add_header = noop,
        },
        timer = {
            at = function(_, fn) return nil end,
            every = function(_, fn) return nil end,
        },
        shared = {
            app_test_cache = {
                get = function() return nil end,
                set = function() return true end,
                delete = noop,
                get_keys = empty_table,
                flush_all = noop,
            },
        },
    }

    _G.ngx = ngx

    -- `require("ngx.resp")` is used by http/response.lua
    package.preload["ngx.resp"] = function()
        return ngx.resp
    end
end

-----------------------------------------------------------------------
-- lfs (LuaFileSystem) – used by Tilua.utils.path
-----------------------------------------------------------------------
if not package.preload["lfs"] then
    local ok_lfs = pcall(require, "lfs")
    if not ok_lfs then
        package.preload["lfs"] = function()
            return {
                attributes = function(path, what)
                    if what == "mode" then
                        return "directory"
                    end
                    return 1700000000
                end,
                currentdir = function() return "." end,
                dir = function() return function() return nil end end,
                mkdir = function() return true end,
                rmdir = function() return true end,
                chdir = function() return true end,
                symlinkattributes = function() return nil end,
                touch = function() return true end,
            }
        end
    end
end

-----------------------------------------------------------------------
-- Optional third-party modules Tilua requires at load time.
-- Stubbed here purely so container/lifecycle wiring can be tested without the
-- full dependency set installed.  A real deployment must provide these (see
-- docs/ANALYSIS.md §5.1/§5.2 for the hard-dependency findings).
-----------------------------------------------------------------------
if not package.preload["resty.jit-uuid"] then
    package.preload["resty.jit-uuid"] = function()
        local counter = 0
        local mod = {}
        mod.seed = function() return true end
        mod.flush = function() return true end
        mod.new = function()
            counter = counter + 1
            return string.format("00000000-0000-4000-8000-%012d", counter)
        end
        -- callable, like the real module
        return setmetatable(mod, {
            __call = function()
                return mod.new()
            end,
        })
    end
end

if not package.preload["random"] then
    package.preload["random"] = function()
        return {
            bytes = function(n) return string.rep("0", n or 1) end,
        }
    end
end

-- Tilua.view rendering is now backed by Tilua.template (plain Lua, no
-- external dependency), so no resty.template stub is needed here anymore.

-----------------------------------------------------------------------
-- run the requested test file in this environment
-----------------------------------------------------------------------
local chunk, err = loadfile(target)
if not chunk then
    io.stderr:write("cannot load " .. target .. ": " .. tostring(err) .. "\n")
    os.exit(2)
end

local ok, result = pcall(chunk)
if not ok then
    io.stderr:write("error running " .. target .. ":\n" .. tostring(result) .. "\n")
    os.exit(1)
end
