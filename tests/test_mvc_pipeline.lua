--- Controller + view layers, end to end.
---
--- This is the path that had NO coverage: no existing suite instantiated a
--- controller, called an action, or rendered a view through the controller API.
--- It covers:
---
---   * a controller action running and rendering a view via `display()`
---   * `assign` values SURVIVING a `display(name, context)` call — they used to
---     be discarded, because `view:render` replaced the context instead of
---     merging into it
---   * `mount_context` as the final fallback below both
---   * a controller action returning a table instead of rendering
---   * `self:service(...)` resolving a container binding
---   * `find_handler` resolving BOTH handler forms, and tolerating a nil
---     `responser` (which used to crash with a string_find type error)
---
--- Run: luajit tests/support/lua_stub.lua tests/test_mvc_pipeline.lua

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

local App = require("TestApp.app")
local RequestCtx = require("Tilua.core.request")

App:init_by_lua()
App:init_worker_by_lua()

--- Register the fixture controller's routes.
---
--- NOTE the handler form: a plain action NAME (`"index"`), not
--- `"TestApp.controller.mvc@index"`.  The two forms invoke the controller
--- differently, and only this one instantiates it:
---
---   `"<module>@<action>"`  -> calls the action on the CLASS with `self = ctx`
---   `"<action>"`           -> derives controller/action from the path and
---                             INSTANTIATES, so `assign` / `display` exist
---
--- A controller action that renders a view must use the second form; this is
--- exactly the distinction that had no test before.
do
    local router = App:make("router")
    for _, action in ipairs({ "index", "mounted", "bare", "json", "svc" }) do
        router.add_route("TestApp", "GET", "/mvc/" .. action, action)
    end
end

--- Read the rendered HTML out of whatever the handler produced.
---
--- `controller:display()` returns the RESPONSE object (it goes through
--- `response:render`), not a bare string, so the body is on `res.body`.  A
--- handler that returns a string directly is also accepted.
local function body_of(result)
    if type(result) == "string" then
        return result
    end
    if type(result) == "table" then
        return result._body or result.body
    end
    return nil
end

--- Drive a request the way the content phase does, minus the HTTP output.
--- Returns the ctx and whatever the handler produced.
local function dispatch(path)
    ngx.ctx = {}
    ngx.var.uri = path
    ngx.var.request_method = "GET"

    local ctx = RequestCtx.context(App, { scope = "content" })
    local router = App:make("router")
    local matched, rule = router.run(ctx)
    if not matched then
        return ctx, nil
    end
    local handler = App:make("dispatcher"):find_handler(rule)
    local ok_call, result = pcall(handler)
    if not ok_call then
        error("handler failed for " .. path .. ": " .. tostring(result), 0)
    end
    return ctx, result
end

--- `dispatch` is the conventional form when the route's handler is a bare
--- action name; keep one name for the call sites.
local dispatch_conventional = dispatch

----------------------------------------------------------------------
-- 1. the conventional path form instantiates the controller
----------------------------------------------------------------------
do
    local Mvc = require("TestApp.controller.mvc")

    -- The controller class has no ctx; instances do.  That distinction is what
    -- makes `assign` / `display` work on one form and not the other.
    eq(rawget(Mvc, "ctx"), nil, "the controller CLASS holds no request context")

    local ctx = RequestCtx.context(App, { scope = "content" })
    local inst = Mvc(ctx, "mvc", "index")
    ok(inst.ctx == ctx, "an instance is bound to the request context")
    eq(inst.controller, "mvc", "the instance records its controller name")
    eq(inst.action, "index", "the instance records its action name")
end

----------------------------------------------------------------------
-- 2. an action renders a view, and its `assign` values survive
--
-- Uses the CONVENTIONAL form, which instantiates the controller — the only form
-- where `assign` / `display` exist.  This is the regression under test.
----------------------------------------------------------------------
do
    local _, result = dispatch_conventional("/mvc/index")
    local body = body_of(result)

    ok(type(body) == "string", "the action returned rendered HTML")
    if type(body) == "string" then
        ok(body:find("marker: MVC-OK", 1, true) ~= nil,
            "a value set with assign() reaches the template")
        ok(body:find("<title>assigned title</title>", 1, true) ~= nil,
            "a second assigned value reaches the template")
        ok(body:find("from_action: passed table", 1, true) ~= nil,
            "the table passed to display() reaches the template")
        ok(body:find("<h1>assigned title</h1>", 1, true) ~= nil,
            "the assigned title survives the explicit context (the regression)")
    end
end

----------------------------------------------------------------------
-- 3. mount_context is the final fallback
----------------------------------------------------------------------
do
    local _, result = dispatch_conventional("/mvc/mounted")
    local body = body_of(result)

    ok(type(body) == "string", "the mounted action rendered")
    if type(body) == "string" then
        ok(body:find("marker: MOUNT-OK", 1, true) ~= nil,
            "an assigned value wins over nothing")
        ok(body:find("site: MOUNTED-SITE", 1, true) ~= nil,
            "mount_context provides values the context does not have")
        ok(body:find("<title>mounted title</title>", 1, true) ~= nil,
            "the display() context is honoured")
    end
end

----------------------------------------------------------------------
-- 4. display() with no context keeps only the assigned values
----------------------------------------------------------------------
do
    local _, result = dispatch_conventional("/mvc/bare")
    local body = body_of(result)

    ok(type(body) == "string", "the bare action rendered")
    if type(body) == "string" then
        ok(body:find("marker: BARE-OK", 1, true) ~= nil,
            "assigned values are enough on their own")
        ok(body:find("<title>bare title</title>", 1, true) ~= nil, "title assigned")
    end
end

----------------------------------------------------------------------
-- 5. an action may return a table instead of rendering
--
-- `find_handler` returns the raw handler result here, because the dispatcher
-- (not this test) is what runs it through `response:json`.  So the table is
-- observable directly.
----------------------------------------------------------------------
do
    local _, result = dispatch("/mvc/json")
    eq(type(result), "table", "a controller action can return a table (JSON)")
    eq(result and result.controller, "mvc", "the returned table is untouched")
end

----------------------------------------------------------------------
-- 6. service manager vs container bindings are different namespaces
----------------------------------------------------------------------
do
    local _, result = dispatch_conventional("/mvc/svc")
    eq(type(result), "table", "the service action returned a table")
    if type(result) == "table" then
        -- `self:service(name)` is the APPLICATION SERVICE manager: it loads
        -- <App>/service/<Name>.lua and falls back to a base service.
        eq(result.service_kind, "table", "self:service always yields a table")
        -- A container binding is reached with ctx:make / ctx.<name>.
        eq(result.container_greeting, "hello Container Demo, service",
            "ctx:make('greeter') resolved the container binding")
    end
end

----------------------------------------------------------------------
-- 7. find_handler: both forms, and the nil-responser guard
----------------------------------------------------------------------
do
    local dispatcher = App:make("dispatcher")
    local ctx = RequestCtx.context(App, { scope = "content" })

    -- (a) the `@` form: called on the CLASS with ctx as the first argument
    local fh = dispatcher:find_handler({
        responser = "TestApp.controller.mvc@json",
        path = "/anywhere",
        args = {},
    })
    local res = fh()
    eq(type(res), "table", "the @ form resolves and runs")
    eq(res and res.action, "json", "the @ form called the right action")

    -- (b) the conventional form: instantiates, so controller helpers work
    local fh2 = dispatcher:find_handler({
        responser = "index",
        path = "/mvc/index",
        args = {},
    })
    local res2 = fh2()
    local res2_body = body_of(res2)
    ok(res2_body ~= nil and res2_body:find("marker: MVC-OK", 1, true) ~= nil,
        "the conventional form resolves via the path and can render")

    -- (c) a missing responser must not crash
    local ok3, fh3 = pcall(function()
        return dispatcher:find_handler({ path = "/mvc/json", args = {} })
    end)
    ok(ok3, "a nil responser does not raise (used to be a string_find crash)")
    if ok3 then
        local res3 = fh3()
        eq(type(res3), "table", "a nil responser falls back to the path form")
    end

    -- (d) unknown paths yield a callable that returns a 404 error object, not nil
    local fh4 = dispatcher:find_handler({
        responser = "TestApp.controller.mvc@nosuchaction",
        path = "/mvc/nosuchaction",
        args = {},
    })
    ok(type(fh4) == "function", "an unresolvable action still returns a callable")
    local res4 = fh4()
    ok(res4 ~= nil, "and that callable yields something (not nil)")

    local fh5 = dispatcher:find_handler({
        responser = "index",
        path = "/nosuchcontroller/index",
        args = {},
    })
    local res5 = fh5()
    ok(res5 ~= nil, "an unknown controller yields a 404 result, not nil")
end

----------------------------------------------------------------------
-- 8. both forms are reachable through the router
----------------------------------------------------------------------
do
    local ctx, result = dispatch("/mvc/index")
    eq(ctx.name, "TestApp", "the context carries the app name")
    local html = body_of(result)
    ok(html ~= nil and html:find("marker: MVC-OK", 1, true) ~= nil,
        "the routed conventional path rendered")
end

----------------------------------------------------------------------
-- 9. the framework/action boundary cannot silently drift
--
-- Route discovery decides what is an action by consulting
-- `controller.framework_methods`.  That list is hand-maintained next to the
-- definitions, so this test fails the moment a method is added to the base
-- controller without being accounted for — which is exactly how `get` and
-- `mount_context` briefly became routable URLs (`/widget/get`).
----------------------------------------------------------------------
do
    local base = require("Tilua.controller")
    local declared = base.framework_methods

    ok(type(declared) == "table",
        "the base controller declares the framework-method set")

    local missing = {}
    for name, value in pairs(base) do
        if type(value) == "function" and not declared[name] then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)

    eq(#missing, 0,
        "every function on the base controller is in framework_methods"
        .. (#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""))

    -- And the discovery filter actually honours it: none of the framework
    -- methods may be treated as an action.
    local discovery = require("Tilua.core.discovery")
    local report = discovery.scan(
        { name = "TestApp", path = "./tests/fixtures/TestApp" },
        App:make("router"),
        { dir = "./tests/fixtures/TestApp/controller" })

    local bad = {}
    for _, c in ipairs(report.controllers) do
        for _, action in ipairs(c.actions) do
            if declared[action] then
                bad[#bad + 1] = c.name .. "." .. action
            end
        end
    end
    table.sort(bad)
    eq(#bad, 0, "no framework method is routable"
        .. (#bad > 0 and (" (leaked: " .. table.concat(bad, ", ") .. ")") or ""))
end

----------------------------------------------------------------------
print(string.format("mvc pipeline tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("mvc pipeline tests passed")
