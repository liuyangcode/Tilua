--- Smoke tests for Tilua.core.helpers
local h = require("Tilua.core.helpers")

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
    end
end

assert_eq(h.strip("  hi  "), "hi")
local parts = h.split("a/b/c", "/", true)
assert_eq(#parts, 3)
assert_eq(parts[2], "b")

local rev = h.reverse({1, 2, 3})
assert_eq(rev[1], 3)
assert_eq(rev[3], 1)

local sum = h.reduce(function(a, b) return a + b end, {1, 2, 3}, 0)
assert_eq(sum, 6)

assert_eq(h.empty(nil), true)
assert_eq(h.empty(""), true)
assert_eq(h.empty({}), true)
assert_eq(h.empty("x"), false)

local f = h.bind1(function(a, b) return a .. b end, "Hello ")
assert_eq(f("world"), "Hello world")

print("helpers smoke tests passed")
