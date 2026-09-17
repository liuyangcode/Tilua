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

        -- Encoding / hashing.  These are implemented rather than stubbed as
        -- identity: an identity `encode_base64` hides real charset bugs (session
        -- ids stopped passing valid_key because base64 emitted "+", "/", "=").
        md5 = function(s)
            -- not a real MD5; only needs to be a stable 16-byte binary digest
            local out, acc = {}, 0
            s = tostring(s)
            for i = 1, #s do
                acc = (acc * 31 + s:byte(i)) % 4294967296
            end
            for i = 0, 15 do
                out[#out + 1] = string.char((math.floor(acc / (2 ^ (i % 4))) + i * 7) % 256)
            end
            return table.concat(out)
        end,
        encode_base64 = function(s, no_padding)
            local alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local out = {}
            s = tostring(s)
            for i = 1, #s, 3 do
                local a1, a2, a3 = s:byte(i, i + 2)
                local v = a1 * 65536 + (a2 or 0) * 256 + (a3 or 0)
                out[#out + 1] = alpha:sub(math.floor(v / 262144) % 64 + 1,
                                          math.floor(v / 262144) % 64 + 1)
                    .. alpha:sub(math.floor(v / 4096) % 64 + 1,
                                 math.floor(v / 4096) % 64 + 1)
                    .. (a2 and alpha:sub(math.floor(v / 64) % 64 + 1,
                                         math.floor(v / 64) % 64 + 1)
                        or (no_padding and "" or "="))
                    .. (a3 and alpha:sub(v % 64 + 1, v % 64 + 1)
                        or (no_padding and "" or "="))
            end
            return table.concat(out)
        end,
        decode_base64 = function(s) return tostring(s) end,
        escape_uri = function(s) return tostring(s) end,
        unescape_uri = function(s) return tostring(s) end,
        quote_sql_str = function(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end,

        -- logging
        log = noop,
        print = function(...) io.write(...) end,
        say = function(...) io.write(table.concat({ ... }, "\t"), "\n") end,
        -- NOT `os.exit`: `response:send()` ends with `ngx.exit(status)`, which
        -- in real OpenResty terminates the request but here would terminate the
        -- whole test process — silently truncating any suite that drives the
        -- content phase (the test simply stopped, exit code 200, no summary).
        -- Raising a distinguishable error lets a test pcall the request.
        exit = function(code)
            error(setmetatable({ ngx_exit = true, code = code or 0 },
                { __tostring = function(t) return "ngx.exit(" .. t.code .. ")" end }), 0)
        end,
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
            local function shell_ok(cmd)
                local ok = os.execute(cmd)
                if ok == true then return true end
                if type(ok) == "number" then return ok == 0 end
                return false
            end

            local function q(path)
                return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
            end

            return {
                --- Real mode/size/times, not a hard-coded "directory".
                ---
                --- A stub that reports every path as a directory is worse than no
                --- stub: code branching on `lfs.attributes(p, "mode")` takes the
                --- directory path for FILES too, silently changing behaviour in the
                --- same direction as a bug.  That is exactly what happened with the
                --- missing `modification` field (see the e2e lfs stub).
                attributes = function(path, what)
                    if type(path) ~= "string" or path == "" then
                        return nil
                    end

                    local ftype, size = "other", 0
                    local f = io.open(path, "rb")
                    if f then
                        -- On Linux io.open succeeds for directories too, so probe
                        -- explicitly rather than trusting the open.
                        if shell_ok("test -d " .. q(path)) then
                            ftype = "directory"
                        else
                            ftype = "file"
                            local n = f:seek("end")
                            if n then size = n end
                        end
                        f:close()
                    else
                        if shell_ok("test -d " .. q(path)) then
                            ftype = "directory"
                        else
                            return nil
                        end
                    end

                    local attr = {
                        mode = ftype,
                        size = size,
                        modification = 1700000000,
                        access = 1700000000,
                        change = 1700000000,
                    }
                    if what then return attr[what] end
                    return attr
                end,
                currentdir = function() return "." end,

                --- Real directory listing.
                ---
                --- This used to be `function() return function() return nil end end`
                --- — an iterator that never yields.  Any code that enumerated a
                --- directory therefore saw it as EMPTY, which is worse than no stub
                --- at all: it silently changes behaviour in the same direction as a
                --- bug (the same failure mode that `attributes` had, see the note in
                --- the e2e lfs stub).  Uses `ls -a`, like the real lfs includes "." and "..".
                dir = function(path)
                    local names = {}
                    local f = io.popen("ls -a " .. q(path) .. " 2>/dev/null")
                    if f then
                        for line in f:lines() do
                            names[#names + 1] = line
                        end
                        f:close()
                    end
                    local i = 0
                    return function()
                        i = i + 1
                        return names[i]
                    end
                end,

                mkdir = function(path)
                    return shell_ok("mkdir -p " .. q(path))
                end,
                rmdir = function(path)
                    shell_ok("rmdir " .. q(path) .. " 2>/dev/null")
                    return true
                end,
                chdir = function() return true end,
                symlinkattributes = function() return nil end,
                touch = function(path)
                    shell_ok("touch " .. q(path))
                    return true
                end,
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
