--- Smoke tests for middleware manager (no OpenResty runtime required for parse/load)
local mw = require("Tilua.middleware")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed") end
end

-- load aliases
mw.load({
    middleware_alias = {
        json = "Tilua.middleware.json_response",
        session = "Tilua.middleware.session",
    },
    middleware_group = {
        api = { "session", "json" },
    },
})

local parsed = mw.parse("session|json")
assert_true(type(parsed) == "table", "parse returns table")
assert_true(#parsed >= 1, "parse yields entries")

local group = mw.get_group("api")
assert_true(type(group) == "table", "get_group api")

print("middleware smoke tests passed")
