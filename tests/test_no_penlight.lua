--- Tests for the pure-Lua package searchpath fallback and the helpers that
--- replaced Penlight (`Tilua.core.helpers`).
---
--- Run: luajit tests/support/lua_stub.lua tests/test_no_penlight.lua
---
--- Why this exists: the project used to soft-load Penlight (`pl.tablex`,
--- `pl.pretty`) and speculatively `pl.dir`, with hand-rolled fallbacks.  Penlight
--- is absent from a stock OpenResty, so those branches were dead code and the
--- fallbacks were never exercised.  Removing Penlight means the replacements ARE
--- the implementation now, so they need direct tests.

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
-- 1. no Penlight reference survives anywhere in the shipped code
----------------------------------------------------------------------
do
    -- Collect candidates with `find` rather than lfs.dir: the shared harness
    -- stubs lfs.attributes as "always a directory", which would recurse forever.
    local offenders, scanned = {}, 0
    local p = io.popen("find Tilua -name '*.lua' 2>/dev/null")
    if p then
        for file in p:lines() do
            scanned = scanned + 1
            local f = io.open(file, "r")
            if f then
                local n = 0
                for line in f:lines() do
                    n = n + 1
                    -- strip comments so documentation mentions do not count
                    local code = line:gsub("%-%-.*$", "")
                    -- require("pl.x") / require('pl.x') / require'pl.x';
                    -- the `%w` after `pl` keeps prose like "require('pl...')" out
                    if code:find("require%s*%(?%s*[\"']pl[%.][%w_]") then
                        offenders[#offenders + 1] = file .. ":" .. n .. "  " .. line
                    end
                end
                f:close()
            end
        end
        p:close()
    end
    ok(scanned > 50, "scanned the framework sources (" .. scanned .. " files)")
    eq(#offenders, 0, "no require('pl...') remains in Tilua/")
    for _, o in ipairs(offenders) do
        io.stderr:write("  " .. o .. "\n")
    end
end

----------------------------------------------------------------------
-- 2. package searchpath fallback matches the runtime's built-in
----------------------------------------------------------------------
do
    local path = require("Tilua.utils.path")
    local fallback = path._searchpath_fallback
    ok(type(fallback) == "function", "path._searchpath_fallback is exposed")

    -- A module that definitely resolves (this file requires it).
    local name = "Tilua.utils.util"
    local expected = package.searchpath and package.searchpath(name, package.path) or nil

    local got = fallback(name, package.path)
    ok(got ~= nil, "fallback finds an existing module")
    if expected then
        eq(got, expected, "fallback agrees with the built-in searchpath")
    end
    ok(got and got:sub(-4) == ".lua", "resolved path is a .lua file")

    -- A module that does not exist must return nil + a useful message.
    local missing, err = fallback("definitely.not.a.module", package.path)
    eq(missing, nil, "fallback returns nil for a missing module")
    ok(type(err) == "string" and err:find("no file", 1, true) ~= nil,
        "fallback explains what it tried")

    -- Bad arguments must not throw.
    local a, b = fallback(nil, nil)
    eq(a, nil, "fallback tolerates nil name/template")
    ok(type(b) == "string", "fallback returns an error string for bad args")

    -- And searchpath() itself still prefers the built-in when present.
    if package.searchpath then
        eq(path._searchpath(name, package.path), expected,
            "searchpath() uses the built-in when available")
    end
end

----------------------------------------------------------------------
-- 3. helpers.update (replaces pl.tablex.update)
----------------------------------------------------------------------
do
    local h = require("Tilua.core.helpers")

    -- arrays append rather than overwrite
    local t = { 1, 2 }
    h.update(t, { 3, 4 })
    eq(#t, 4, "update appends array elements")
    eq(t[3], 3, "update appended the first new element")
    eq(t[4], 4, "update appended the second new element")

    -- nested arrays merge recursively
    local n = { a = { 1, 2 } }
    h.update(n, { a = { 3 } })
    eq(#n.a, 3, "update merges nested arrays")
    eq(n.a[3], 3, "update appended into the nested array")

    -- scalars overwrite
    local s = { a = 1, b = 2 }
    h.update(s, { a = 9 })
    eq(s.a, 9, "update overwrites scalars")
    eq(s.b, 2, "update leaves untouched keys alone")

    -- nil / non-table input is tolerated
    eq(h.update(nil, { 1 }), nil, "update(nil, t) returns nil")
    eq(type(h.update({}, nil)), "table", "update(t, nil) returns the table")

    -- `extend` must stay a FLAT overwrite (config-merge semantics) — making it
    -- append would duplicate middleware lists in configs.
    local e = { 1, 2 }
    h.extend(e, { 3, 4 })
    eq(#e, 2, "extend overwrites rather than appends")
    eq(e[1], 3, "extend overwrote index 1")
end

----------------------------------------------------------------------
-- 4. helpers.size / foreach (replaces pl.tablex.size / foreach)
----------------------------------------------------------------------
do
    local h = require("Tilua.core.helpers")
    eq(h.size({}), 0, "size of an empty table")
    eq(h.size({ 1, 2, 3 }), 3, "size counts the array part")
    eq(h.size({ a = 1, b = 2 }), 2, "size counts the hash part")
    eq(h.size({ 1, 2, a = 1 }), 3, "size counts both parts")
    eq(h.size(nil), 0, "size of nil is 0")

    local seen = {}
    h.foreach({ b = 2, a = 1, c = 3 }, function(v, k)
        seen[#seen + 1] = k .. "=" .. v
    end)
    eq(table.concat(seen, ","), "a=1,b=2,c=3", "foreach iterates in key order")
    ok(pcall(h.foreach, { 1 }, nil) ~= nil, "foreach tolerates a nil callback")
end

----------------------------------------------------------------------
-- 5. helpers.pretty (replaces pl.pretty.write)
----------------------------------------------------------------------
do
    local h = require("Tilua.core.helpers")

    eq(h.pretty({}), "{}", "pretty of an empty table")
    eq(h.pretty(42), "42", "pretty of a number")
    eq(h.pretty(true), "true", "pretty of a boolean")
    eq(h.pretty('a"b'), '"a\\"b"', "pretty escapes strings")

    local out = h.pretty({ n = 1, s = "x", t = { 1, 2 } })
    local chunk = (loadstring or load)("return " .. out)
    ok(chunk ~= nil, "pretty output is valid Lua")
    if chunk then
        local v = chunk()
        eq(v.s, "x", "pretty output round-trips a string")
        eq(v.t[2], 2, "pretty output round-trips a nested array")
    end

    -- cyclic tables must not hang
    local cyc = {}
    cyc.self = cyc
    local cyc_out = h.pretty(cyc)
    ok(cyc_out:find("<cycle>", 1, true) ~= nil, "pretty reports cycles")

    -- keys that are not valid identifiers must still round-trip
    local weird = h.pretty({ ["a b"] = 1 })
    local wchunk = (loadstring or load)("return " .. weird)
    ok(wchunk ~= nil, "pretty handles non-identifier keys")
    if wchunk then
        eq(wchunk()["a b"], 1, "pretty round-trips a non-identifier key")
    end
end

----------------------------------------------------------------------
print(string.format("no-Penlight tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("no-Penlight tests passed")
