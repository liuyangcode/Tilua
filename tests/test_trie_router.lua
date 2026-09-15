--- Trie router tests.
--- Run: luajit tests/support/lua_stub.lua tests/test_trie_router.lua
---
--- Notes on the harness: `tests/support/lua_stub.lua` supplies an ngx.re stub
--- whose `match`/`find` always return nil.  Regex-fallback assertions are
--- therefore marked and skipped unless a real ngx is present; everything else
--- (the trie itself) is pure Lua and fully exercised.

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

local function skip(label)
    checks = checks + 1
    io.write("SKIP: " .. label .. "\n")
end

--- Fresh router state per scenario so caches cannot leak between them.
local function fresh_router(app)
    package.loaded["Tilua.http.router"] = nil
    local route = require("Tilua.http.router")
    route.set_app_name(app or "TestApp")
    return route
end

--- Register rules and compile them in one step.
local function compile(route, rules)
    for _, r in ipairs(rules) do
        local h = r[3] or function() return r[1] end
        route[r[1]](r[2], h)
    end
    route.init_rule_caches({})
    return route
end

--- handler identity helper: rules carry the handler we registered
local function who(rule)
    return rule and rule.responser or nil
end

-----------------------------------------------------------------------
-- 1. static routes match exactly, and nothing else
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_home    = function() return "home" end
    local h_greeter = function() return "greeter" end
    local h_text    = function() return "text" end

    route.get("/", h_home)
    route.get("/greeter", h_greeter)
    route.get("/text", h_text)

    route.init_rule_caches({})

    local r, caps = route.match("TestApp", "get", "/greeter")
    ok(r ~= nil, "/greeter matches")
    eq(who(r), h_greeter, "/greeter dispatches its own handler")
    eq(#caps, 0, "/greeter has no captures")

    local r2 = route.match("TestApp", "get", "/text")
    eq(who(r2), h_text, "/text dispatches its own handler, not /greeter's")

    local r3 = route.match("TestApp", "get", "/")
    eq(who(r3), h_home, "/ matches the root route")

    --- THE regression that motivated the rewrite: an unknown path must NOT
    --- match "/" via prefix semantics.
    eq(route.match("TestApp", "get", "/nope"), nil, "/nope does not match '/'")
    eq(route.match("TestApp", "get", "/greeter/extra"), nil, "/greeter/extra does not match")
    eq(route.match("TestApp", "get", "/greet"), nil, "/greet does not match /greeter")
end

-----------------------------------------------------------------------
-- 2. {name} single-segment parameters
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h = function() end
    route.get("/user/{name}", h)
    route.init_rule_caches({})

    local r, caps = route.match("TestApp", "get", "/user/ada")
    ok(r ~= nil, "/user/{name} matches /user/ada")
    eq(who(r), h, "param route dispatches its handler")
    eq(caps.name, "ada", "captures the parameter by name")

    eq(route.match("TestApp", "get", "/user"), nil, "/user alone does not match")
    eq(route.match("TestApp", "get", "/user/a/b"), nil, "{name} captures one segment only")

    --- "/user/" normalises to "/user" (one segment), so it correctly does NOT
    --- match a two-segment "{name}" route.
    eq(route.match("TestApp", "get", "/user/"), nil,
        "trailing slash does not manufacture a parameter segment")
end

-----------------------------------------------------------------------
-- 3. static beats {name} at the same position
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_new = function() return "new" end
    local h_id  = function() return "id" end

    -- deliberately register the param route FIRST
    route.get("/user/{id}", h_id)
    route.get("/user/new", h_new)
    route.init_rule_caches({})

    local r = route.match("TestApp", "get", "/user/new")
    eq(who(r), h_new, "static /user/new wins over /user/{id} regardless of order")

    local r2, caps = route.match("TestApp", "get", "/user/42")
    eq(who(r2), h_id, "non-static segment falls through to {id}")
    eq(caps.id, "42", "param route still captures")
end

-----------------------------------------------------------------------
-- 4. deeper nesting and multiple params
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h = function() end
    route.get("/api/v1/user/{uid}/post/{pid}", h)
    route.init_rule_caches({})

    local r, caps = route.match("TestApp", "get", "/api/v1/user/7/post/9")
    ok(r ~= nil, "deep nested param route matches")
    eq(caps.uid, "7", "first param captured")
    eq(caps.pid, "9", "second param captured")

    eq(route.match("TestApp", "get", "/api/v1/user/7/post"), nil, "missing tail does not match")
    eq(route.match("TestApp", "get", "/api/v1/user/7/post/9/x"), nil, "extra segment does not match")
end

-----------------------------------------------------------------------
-- 5. wildcards
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_files = function() end
    local h_static = function() end

    route.get("/files/*", h_files)
    route.get("/files/readme", h_static)
    route.init_rule_caches({})

    local r, caps = route.match("TestApp", "get", "/files/a/b/c.txt")
    eq(who(r), h_files, "wildcard matches a deep remainder")
    eq(caps.splat, "a/b/c.txt", "wildcard captures the remainder")

    --- specific route still wins over the wildcard
    local r2 = route.match("TestApp", "get", "/files/readme")
    eq(who(r2), h_static, "specific route beats wildcard")

    local r3, caps3 = route.match("TestApp", "get", "/files/")
    ok(r3 ~= nil, "wildcard matches the empty remainder")
    eq(caps3.splat, "", "empty remainder captures as empty string")
end

-----------------------------------------------------------------------
-- 6. named wildcard
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h = function() end
    route.get("/assets/{path*}", h)
    route.init_rule_caches({})

    local r, caps = route.match("TestApp", "get", "/assets/css/app.css")
    ok(r ~= nil, "named wildcard matches")
    eq(caps.path, "css/app.css", "named wildcard uses the given name")
end

-----------------------------------------------------------------------
-- 7. methods
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_get  = function() end
    local h_post = function() end
    route.get("/thing", h_get)
    route.post("/thing", h_post)
    route.init_rule_caches({})

    eq(who(route.match("TestApp", "get", "/thing")), h_get, "GET resolves the GET rule")
    eq(who(route.match("TestApp", "post", "/thing")), h_post, "POST resolves the POST rule")
    eq(route.match("TestApp", "delete", "/thing"), nil, "unregistered method does not match")
end

-----------------------------------------------------------------------
-- 8. prefix routes ("* /api") still work, via a trie wildcard
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_api = function() end
    route["* /api"] = h_api
    route.init_rule_caches({})

    local r = route.match("TestApp", "get", "/api/anything/here")
    ok(r ~= nil, "prefix route matches a longer path")
    local r2 = route.match("TestApp", "get", "/apifoo")
    eq(r2, nil, "prefix route respects a segment boundary (/apifoo must not match)")
end

-----------------------------------------------------------------------
-- 9. trailing slash and duplicate slash normalisation
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h = function() end
    route.get("/about", h)
    route.init_rule_caches({})

    eq(who(route.match("TestApp", "get", "/about/")), h, "trailing slash matches")
    eq(who(route.match("TestApp", "get", "//about")), h, "duplicate slash matches")
    eq(who(route.match("TestApp", "get", "/about//")), h, "mixed slashes match")
end

-----------------------------------------------------------------------
-- 10. route.run over a request context
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local h_user = function() end
    route.get("/user/{name}", h_user)
    route.init_rule_caches({})

    local function make_ctx(uri)
        ngx.var.uri = uri
        ngx.var.request_method = "GET"
        local request = { method = "GET", path_info = uri }
        return {
            name = "TestApp",
            make = function(_, what)
                if what == "request" then return request end
                error("unexpected service: " .. tostring(what))
            end,
        }
    end

    local matched, rule = route.run(make_ctx("/user/ada"))
    ok(matched, "run() reports a match")
    eq(who(rule), h_user, "run() returns the matched rule")
    eq(rule.vals.name, "ada", "run() exposes captures via rule.vals")

    local matched2, path = route.run(make_ctx("/nope"))
    ok(not matched2, "run() reports no match for an unknown path")
    eq(path, "/nope", "run() returns the normalised path when unmatched")
end

-----------------------------------------------------------------------
-- 11. named rules do not collide at the same dynamic position
-----------------------------------------------------------------------
do
    local route = fresh_router()
    route.get("/u/{id}", function() end)
    route.get("/u/{name}", function() end)
    route.init_rule_caches({})

    --- whichever name was registered first owns the node; the point is that
    --- matching is deterministic and captures under exactly one name.
    local r, caps = route.match("TestApp", "get", "/u/x")
    ok(r ~= nil, "conflicting param names still match")
    local count = 0
    for _ in pairs(caps) do count = count + 1 end
    eq(count, 1, "exactly one capture name is used")
    ok(caps.id == "x" or caps.name == "x", "capture uses one of the declared names")
end

-----------------------------------------------------------------------
-- 12. path helpers used elsewhere in the framework
-----------------------------------------------------------------------
do
    local route = fresh_router()
    local _, regex, params = route.parse_path_to_regex("/user/{name}")
    eq(params[1], "name", "parse_path_to_regex reports param names")
    ok(regex:find("^%^/") ~= nil, "parse_path_to_regex anchors at the start")
    ok(regex:find("%$$") ~= nil, "parse_path_to_regex anchors at the end")

    local method, matcher, url = route.parse_rule("get /plain")
    eq(matcher, "=", "unprefixed paths default to EXACT")
    eq(url, "/plain", "parse_rule strips no characters for exact paths")
    eq(method[1], "get", "parse_rule returns the method list")

    local _, m2, u2 = route.parse_rule("get ~/u/(%d+)")
    eq(m2, "~", "explicit ~ selects the regex fallback")
    eq(u2, "/u/(%d+)", "regex path preserved")

    local _, m3 = route.parse_rule("get /user/{name}")
    eq(m3, "~", "a leading { selects the regex matcher for validation support")

    local _, m4, u4 = route.parse_rule("* /api")
    eq(m4, "*", "explicit * selects prefix matching")
    eq(u4, "/api", "prefix path preserved")
end

-----------------------------------------------------------------------
print(string.format("trie router tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("trie router tests passed")
