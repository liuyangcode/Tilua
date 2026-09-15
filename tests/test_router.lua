--- Simple smoke tests for the router (run with resty or busted later)
-- Usage (with OpenResty):
--   resty tests/test_router.lua

local route = require("Tilua.http.router")

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assert_eq failed") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
    end
end

-- reset state
route.set_app_name("TestApp")

-- basic exact match
route.get("/", function() return "home" end)
route.get("/hello/{name}", function(ctx, name) return "hi " .. name end)

route.init_rule_caches({})

local matched, router = route.find_matched_route("TestApp", "GET", "/")
assert_eq(matched, true, "root should match")
assert(router, "router object expected")

matched, router = route.find_matched_route("TestApp", "GET", "/hello/world")
assert_eq(matched, true, "param route should match")

matched, router = route.find_matched_route("TestApp", "POST", "/")
-- depending on method filtering may or may not match; just ensure no crash
print("router smoke tests passed")
