--- Controller discovery: convention-based MVC routes.
---
--- `auto_routes = true` scans `<App>/controller/` at worker start and registers
--- a route per public action.  These tests cover the scan itself, the
--- private/inherited filtering, and the precedence rule (an explicit route must
--- win over a discovered one for the same method + path).
---
--- Run: luajit tests/support/lua_stub.lua tests/test_discovery.lua

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

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

----------------------------------------------------------------------
-- 1. discovery is OFF by default
----------------------------------------------------------------------
do
    local default = require("Tilua.config.default")
    eq(default.auto_routes, false,
        "auto_routes defaults to false (discovery is opt-in)")
end

----------------------------------------------------------------------
-- 2. the scan finds the fixture controller and its public actions only
----------------------------------------------------------------------
do
    local header = {
        name = "TestApp",
        path = "./tests/fixtures/TestApp",
        make = function() error("make() not expected during scan") end,
    }

    -- fresh router so the fixture routes cannot interfere
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    local discovery = require("Tilua.core.discovery")
    local report = discovery.scan(header, router, {
        dir = "./tests/fixtures/TestApp/controller",
    })

    -- Errors about *other* fixtures are expected: `annotated.lua` deliberately
    -- contains a bad method and an unknown directive (covered by
    -- tests/test_annotations.lua).  Only this controller must be clean.
    local widget_errors = 0
    for _, e in ipairs(report.errors) do
        if tostring(e):find("widget", 1, true) then
            widget_errors = widget_errors + 1
        end
    end
    eq(widget_errors, 0, "the widget controller scans without errors"
        .. (widget_errors > 0 and (" (" .. table.concat(report.errors, "; ") .. ")") or ""))

    -- The fixture directory holds more than one controller, so assert on the
    -- one under test rather than on a global count.
    local widget
    for _, c in ipairs(report.controllers) do
        if c.name == "widget" then widget = c end
    end

    ok(widget ~= nil, "the widget controller is in the report")

    -- The fixture directory holds more than one controller and grows as
    -- coverage is added, so assert on the routes under test rather than on a
    -- global count.
    local widget_paths = {}
    local widget_routes = 0
    for _, r in ipairs(router.get_route_caches("TestApp") or {}) do
        local p = tostring(r.path)
        if p:find("^/widget/") then
            widget_paths[p] = true
            widget_routes = widget_routes + 1
        end
    end
    eq(widget_routes, 3, "widget contributed exactly three rules (got: "
        .. (function()
            local ks = {}
            for k in pairs(widget_paths) do ks[#ks + 1] = k end
            table.sort(ks)
            return table.concat(ks, ", ")
        end)() .. ")")
    ok(widget_paths["/widget/index"], "widget's index route exists")
    ok(widget_paths["/widget/show"], "widget's show route exists")
    ok(widget_paths["/widget/greet"], "widget's greet route exists")

    if widget then
        eq(widget.name, "widget", "controller name comes from the filename")
        ok(contains(widget.actions, "index"), "index is an action")
        ok(contains(widget.actions, "show"), "show is an action")
        ok(contains(widget.actions, "greet"), "greet is an action")

        ok(not contains(widget.actions, "_helper"),
            "a leading-underscore method is not an action")
        for _, inherited in ipairs({ "assign", "display", "service", "model", "fail", "_call", "_construct" }) do
            ok(not contains(widget.actions, inherited),
                "inherited base method '" .. inherited .. "' is not an action")
        end

        eq(widget.url_base, "/widget/", "url base is /<controller>/")
    end

    router.init_rule_caches({})

    -- the generated routes must actually be matchable
    for _, path in ipairs({ "/widget/index", "/widget/show", "/widget/greet" }) do
        local rule = router.match("TestApp", "get", path)
        ok(rule ~= nil, "GET " .. path .. " matches")
        if rule then
            ok(type(rule.responser) == "string" and rule.responser:find("@", 1, true) ~= nil,
                "the handler is a controller@action string for " .. path)
        end
    end

    ok(router.match("TestApp", "get", "/widget/_helper") == nil,
        "a private method is not routable")
    ok(router.match("TestApp", "get", "/widget/assign") == nil,
        "an inherited base method is not routable")
end

----------------------------------------------------------------------
-- 3. an explicit route beats a discovered one (same method + path)
----------------------------------------------------------------------
do
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    local explicit = function() return "EXPLICIT" end

    -- explicit first, as `init_by_lua` does
    router.get("/widget/index", explicit)
    router.init_rule_caches({})

    local discovery = require("Tilua.core.discovery")
    local header = { name = "TestApp", path = "./tests/fixtures/TestApp" }
    discovery.scan(header, router, { dir = "./tests/fixtures/TestApp/controller" })

    local rule = router.match("TestApp", "get", "/widget/index")
    ok(rule ~= nil, "/widget/index still matches after discovery")
    eq(rule and rule.responser, explicit,
        "the EXPLICIT handler wins over the discovered one")
    eq(rule and rule.source, "explicit", "the winning rule is marked explicit")

    -- and a path only discovery knows is still reachable
    local scanned = router.match("TestApp", "get", "/widget/greet")
    ok(scanned ~= nil, "a discovered-only route still matches")
    eq(scanned and scanned.source, "scanned", "the discovered rule is marked scanned")
end

----------------------------------------------------------------------
-- 4. discovery registered late is visible without a manual rebuild
----------------------------------------------------------------------
do
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    -- boot with no routes at all, then discover
    router.init_rule_caches({})
    eq(router.match("TestApp", "get", "/widget/index"), nil,
        "no route before discovery")

    local discovery = require("Tilua.core.discovery")
    discovery.scan({ name = "TestApp", path = "./tests/fixtures/TestApp" }, router,
        { dir = "./tests/fixtures/TestApp/controller" })

    -- no init_rule_caches here: discovery must be immediately effective
    ok(router.match("TestApp", "get", "/widget/index") ~= nil,
        "a discovered route is reachable immediately, with no rebuild call")
end

----------------------------------------------------------------------
-- 5. a missing controller directory is not an error
----------------------------------------------------------------------
do
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    local discovery = require("Tilua.core.discovery")
    local report = discovery.scan(
        { name = "TestApp", path = "./tests/fixtures/TestApp" }, router,
        { dir = "./tests/fixtures/TestApp/no-such-directory" })

    eq(#report.errors, 0, "a missing controller dir is not an error")
    eq(report.registered, 0, "nothing registered")
    ok(#report.skipped > 0, "the skip is reported")
end

----------------------------------------------------------------------
-- 6. an unset app name is reported, not crashed on
----------------------------------------------------------------------
do
    package.loaded["Tilua.http.router"] = nil
    local router = require("Tilua.http.router")
    router.set_app_name("TestApp")

    local discovery = require("Tilua.core.discovery")
    local report = discovery.scan({ name = "", path = "." }, router, { dir = "." })

    ok(#report.errors > 0, "an unnamed app is reported as an error")
    eq(report.registered, 0, "nothing is registered for an unnamed app")
end

----------------------------------------------------------------------
print(string.format("discovery tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("discovery tests passed")
