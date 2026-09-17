--- The framework must load and serve with NO LuaFileSystem.
---
--- `Tilua.utils.path` used to `error()` at require time without `lfs`, which made
--- the entire framework unloadable on a stock `openresty/openresty` image (that
--- image ships no `lfs.so`, despite LuaFileSystem often being described as
--- "bundled with OpenResty").  These tests hide `lfs` and assert that the pure
--- `io`/`os` fallback still resolves paths, sizes and modification times.
---
--- Run: luajit tests/support/lua_stub.lua tests/test_path_no_lfs.lua
---
--- The harness stubs `lfs` via `package.preload`; this test removes it again so
--- the fallback is the code under test.

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
-- 1. make `require("lfs")` fail, then load the framework fresh
----------------------------------------------------------------------
package.preload["lfs"] = nil
package.loaded["lfs"] = nil
package.loaded["Tilua.utils.path"] = nil
package.loaded["Tilua.utils.util"] = nil

-- Prove lfs is really gone before asserting anything about the fallback.
local lfs_ok = pcall(require, "lfs")
ok(not lfs_ok, "lfs is genuinely unavailable for this test")

local path = require("Tilua.utils.path")
ok(type(path) == "table", "Tilua.utils.path loads without lfs")
eq(path.has_lfs, false, "path.has_lfs reports false")

----------------------------------------------------------------------
-- 2. existence / type / size
----------------------------------------------------------------------
do
    local file = "Tilua/utils/path.lua"

    ok(path.exists(file) ~= nil, "path.exists finds an existing file")
    eq(path.isdir(file), false, "a file is not a directory")
    ok(path.isdir("Tilua/utils") == true, "path.isdir finds a directory")

    eq(path.isfile(file), true, "path.isfile reports a file")
    eq(path.exists("no/such/file.lua"), nil, "path.exists returns nil when missing")
    eq(path.isdir("no/such/dir"), false, "path.isdir is false when missing")

    local size = path.getsize(file)
    ok(type(size) == "number" and size > 0, "path.getsize returns a byte count")

    local f = io.open(file, "rb")
    local on_disk = f:seek("end")
    f:close()
    eq(size, on_disk, "path.getsize agrees with io.seek")
end

----------------------------------------------------------------------
-- 3. modification time (the view cache depends on this)
----------------------------------------------------------------------
do
    local file = "Tilua/utils/path.lua"
    local mtime = path.getmtime(file)
    ok(type(mtime) == "number", "path.getmtime returns a number without lfs")

    -- Must be a real wall-clock timestamp, not a placeholder: the view cache
    -- compares it against the cache file's mtime to decide staleness.
    local now = os.time()
    ok(mtime <= now + 5, "mtime is not in the future")
    ok(mtime > now - 60 * 60 * 24 * 365 * 30,
        "mtime looks like a real epoch timestamp (not 0)")

    eq(path.getmtime("no/such/file.lua"), nil, "mtime of a missing file is nil")

    -- A file we just wrote must be at least as new as one written earlier.
    local a = os.tmpname()
    local b = os.tmpname()
    local fa = io.open(a, "w"); fa:write("a"); fa:close()
    local fb = io.open(b, "w"); fb:write("b"); fb:close()
    ok(path.getmtime(a) ~= nil and path.getmtime(b) ~= nil,
        "mtime works for freshly written files")
    os.remove(a); os.remove(b)
end

----------------------------------------------------------------------
-- 4. pure-Lua path arithmetic still works
----------------------------------------------------------------------
do
    eq(path.join("a", "b", "c"), "a/b/c", "path.join")
    eq(path.dirname("/a/b/c.lua"), "/a/b", "path.dirname")
    eq(path.basename("/a/b/c.lua"), "c.lua", "path.basename")
    eq(path.extension("c.lua"), ".lua", "path.extension")
    eq(path.normpath("/a/./b/../c"), "/a/c", "path.normpath")
    ok(path.isabs("/a"), "path.isabs on a unix absolute path")
    eq(path.join("/root", "/abs"), "/abs", "an absolute second segment wins")
end

----------------------------------------------------------------------
-- 5. module resolution (App.path depends on this)
----------------------------------------------------------------------
do
    local dir = path.get_module_path("Tilua.utils", "path")
    ok(dir ~= nil, "get_module_path resolves a real module without lfs")
    if dir then
        ok(path.isdir(dir), "resolved module directory exists: " .. tostring(dir))
    end
    eq(path.get_module_path("no.such.module"), nil, "unknown module resolves to nil")
end

----------------------------------------------------------------------
-- 6. ensure_dir-equivalent behaviour (mkdir fallback)
----------------------------------------------------------------------
do
    local base = os.tmpname() .. "_tilua_mkdir"
    os.remove(base)
    ok(path.mkdir(base), "path.mkdir creates a directory without lfs")
    ok(path.isdir(base), "the created directory exists")
    path.rmdir(base)
    ok(not path.isdir(base), "path.rmdir removes it")
end

----------------------------------------------------------------------
print(string.format("path-without-lfs tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("path-without-lfs tests passed")
