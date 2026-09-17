--- Plugin hooks must fire on the PHASE path.
---
--- The hooks were only emitted from `App:run()` and `Channel.dispatch()` — the
--- non-phase entry points.  A normal nginx config uses the lifecycle handlers
--- (`rewrite_by_lua` / `access_by_lua` / `content_by_lua` / `log_by_lua`), which
--- emitted nothing except `on_route_loaded`, so the entire plugin system was
--- inert in production.  `on_worker_init` was never emitted at all.
---
--- This drives the real phase handlers and asserts each hook fires, in order,
--- exactly once per request.
---
--- Run: luajit tests/support/lua_stub.lua tests/test_plugin_hooks.lua

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

local Plugin = require("Tilua.core.plugin")
local RequestCtx = require("Tilua.core.request")

--- Run a phase, tolerating the terminal `ngx.exit`.
---
--- `response:send()` finishes with `ngx.exit(status)`.  In real OpenResty that
--- ends the request; the test harness raises a catchable error instead of
--- killing the process (see tests/support/lua_stub.lua).  Any other error is
--- re-raised so a real failure cannot hide behind this wrapper.
local function phase(fn, ...)
    local ok_call, err = pcall(fn, ...)
    if not ok_call then
        if type(err) == "table" and err.ngx_exit then
            return err.code
        end
        error(err, 0)
    end
    return nil
end

----------------------------------------------------------------------
-- A recorder plugin covering every hook.
----------------------------------------------------------------------

local calls        -- ordered log of hook names
local payloads     -- hook -> last arguments captured
local hook_errors  -- hooks that should raise, to prove isolation

local function reset_recorder()
    calls = {}
    payloads = {}
    hook_errors = {}
end

local function recorder()
    return {
        name = "recorder",
        priority = 10,
        hooks = {
            on_boot         = function() calls[#calls + 1] = "on_boot" end,
            on_route_loaded = function() calls[#calls + 1] = "on_route_loaded" end,
            on_worker_init  = function(a, c)
                calls[#calls + 1] = "on_worker_init"
                payloads.on_worker_init = { app = a, ctx = c }
            end,
            on_request = function(a, c)
                calls[#calls + 1] = "on_request"
                payloads.on_request = { app = a, ctx = c }
                if hook_errors.on_request then error("boom in on_request") end
            end,
            on_dispatch = function(a, c, matched, router)
                calls[#calls + 1] = "on_dispatch"
                payloads.on_dispatch = {
                    app = a, ctx = c, matched = matched, router = router,
                }
            end,
            on_response = function(a, c, response)
                calls[#calls + 1] = "on_response"
                payloads.on_response = { app = a, ctx = c, response = response }
            end,
            on_error = function(a, c, ex)
                calls[#calls + 1] = "on_error"
                payloads.on_error = { app = a, ctx = c, ex = ex }
            end,
        },
    }
end

local function count_hook(name)
    local n = 0
    for _, h in ipairs(calls) do
        if h == name then n = n + 1 end
    end
    return n
end

local function index_of_hook(name)
    for i, h in ipairs(calls) do
        if h == name then return i end
    end
    return nil
end

local function new_request(uri, method)
    ngx.ctx = {}
    ngx.var.uri = uri
    ngx.var.request_method = method or "GET"
end

----------------------------------------------------------------------
-- Boot the fixture app with the recorder registered as a plugin.
----------------------------------------------------------------------

Plugin.reset()
reset_recorder()

local App = require("TestApp.app")
Plugin.register(recorder())

App:init_by_lua()

ok(index_of_hook("on_route_loaded") ~= nil,
    "on_route_loaded fires during init_by_lua")

-- `on_boot` belongs to the worker phase: Plugin.boot() runs from boot_worker(),
-- which init_by_lua deliberately does not call.
eq(count_hook("on_boot"), 0, "on_boot does not fire in the master phase")

----------------------------------------------------------------------
-- 1. on_worker_init fires once, and only once, per worker
----------------------------------------------------------------------
do
    App:init_worker_by_lua()
    eq(count_hook("on_worker_init"), 1, "on_worker_init fires on worker boot")
    eq(count_hook("on_boot"), 1, "on_boot fires on worker boot")

    -- Lazy boot: rewrite_by_lua calls init_worker_by_lua when the configured
    -- worker phase is missing.  It must not re-fire the hook.
    App:init_worker_by_lua()
    eq(count_hook("on_worker_init"), 1,
        "a second init_worker_by_lua does not re-fire on_worker_init")

    local p = payloads.on_worker_init
    ok(p ~= nil and p.app == App, "on_worker_init receives the app")
    eq(p and p.ctx, nil, "on_worker_init has no request context")
end

----------------------------------------------------------------------
-- 2. a successful request fires on_request -> on_dispatch -> on_response
----------------------------------------------------------------------
do
    reset_recorder()
    new_request("/greeter")

    phase(App.rewrite_by_lua, App)
    eq(count_hook("on_request"), 1, "on_request fires once in rewrite")

    local ctx = RequestCtx.slot().ctx
    local p = payloads.on_request
    ok(p ~= nil and p.app == App, "on_request receives the app first")
    ok(p ~= nil and p.ctx == ctx, "on_request receives the request context second")

    phase(App.access_by_lua, App)
    eq(count_hook("on_request"), 1, "on_request does not re-fire in access")

    phase(App.content_by_lua, App)
    eq(count_hook("on_dispatch"), 1, "on_dispatch fires once in content")
    eq(count_hook("on_response"), 1, "on_response fires once when the body is sent")

    local d = payloads.on_dispatch
    ok(d ~= nil and d.ctx == ctx, "on_dispatch receives the request context")
    ok(d ~= nil and type(d.matched) == "table",
        "on_dispatch receives the matched RULE (not a boolean)")
    ok(d ~= nil and type(d.router) == "table", "on_dispatch receives the router")

    local r = payloads.on_response
    ok(r ~= nil and r.ctx == ctx, "on_response receives the request context")
    ok(r ~= nil and type(r.response) == "table", "on_response receives the response")
    ok(r ~= nil and r.response.status == 200,
        "on_response sees a normalised 200 status")

    local i_req = index_of_hook("on_request")
    local i_dis = index_of_hook("on_dispatch")
    local i_res = index_of_hook("on_response")
    ok(i_req and i_dis and i_res and i_req < i_dis and i_dis < i_res,
        "hooks fire in request -> dispatch -> response order")

    phase(App.log_by_lua, App)
end

----------------------------------------------------------------------
-- 3. a 404 still fires on_dispatch and on_response (no error)
----------------------------------------------------------------------
do
    reset_recorder()
    new_request("/definitely-not-a-route")

    phase(App.rewrite_by_lua, App)
    phase(App.access_by_lua, App)
    phase(App.content_by_lua, App)

    eq(count_hook("on_request"), 1, "404 request fires on_request")
    eq(count_hook("on_dispatch"), 1, "404 request still fires on_dispatch once")
    eq(payloads.on_dispatch.matched, false, "on_dispatch reports matched=false for a 404")
    eq(count_hook("on_response"), 1, "404 request fires on_response once")
    eq(count_hook("on_error"), 0, "a 404 is not an error hook")

    phase(App.log_by_lua, App)
end

----------------------------------------------------------------------
-- 4. a throwing handler fires on_error, then on_response
----------------------------------------------------------------------
do
    reset_recorder()
    new_request("/boom")

    phase(App.rewrite_by_lua, App)
    phase(App.access_by_lua, App)
    phase(App.content_by_lua, App)

    eq(count_hook("on_error"), 1, "a thrown handler fires on_error once")
    eq(count_hook("on_response"), 1, "the error response still fires on_response")

    local e = payloads.on_error
    ok(e ~= nil and e.ctx ~= nil, "on_error receives the request context")
    ok(e ~= nil and e.ex ~= nil, "on_error receives the exception")
    ok(e ~= nil and (e.ex.status == 500 or e.ex.layer == "controller"),
        "on_error receives a structured exception")

    local i_err = index_of_hook("on_error")
    local i_res = index_of_hook("on_response")
    ok(i_err and i_res and i_err < i_res, "on_error fires before on_response")

    phase(App.log_by_lua, App)
end

----------------------------------------------------------------------
-- 5. a middleware denial fires on_response but not on_dispatch
----------------------------------------------------------------------
do
    reset_recorder()

    -- /admin carries an access-phase guard (admin_guard) in the fixture; with no
    -- token it denies, so the content phase never runs.
    new_request("/admin")
    phase(App.rewrite_by_lua, App)
    phase(App.access_by_lua, App)

    eq(count_hook("on_request"), 1, "denied request fires on_request")
    eq(count_hook("on_response"), 1, "denied request fires on_response once")
    eq(count_hook("on_dispatch"), 0, "a denied request never reaches on_dispatch")
    eq(count_hook("on_error"), 0, "a denial is not an error")

    phase(App.log_by_lua, App)
end

----------------------------------------------------------------------
-- 6. a throwing hook is caught and does not break the request
----------------------------------------------------------------------
do
    reset_recorder()
    hook_errors.on_request = true

    new_request("/greeter")

    local ok_run, err = pcall(function()
        phase(App.rewrite_by_lua, App)
        phase(App.access_by_lua, App)
        phase(App.content_by_lua, App)
    end)

    ok(ok_run, "a throwing on_request hook does not break the request"
        .. (ok_run and "" or (" -- " .. tostring(err))))
    eq(count_hook("on_request"), 1, "the throwing hook still counted as fired")
    eq(count_hook("on_dispatch"), 1, "the request proceeded to dispatch")

    hook_errors.on_request = false
    phase(App.log_by_lua, App)
end

----------------------------------------------------------------------
-- 7. the non-phase entry point still works and does not double-fire
----------------------------------------------------------------------
do
    reset_recorder()
    new_request("/greeter")

    local ok_run, err = pcall(function()
        return App:run()
    end)
    ok(ok_run, "App:run() still works with hooks wired"
        .. (ok_run and "" or (" -- " .. tostring(err))))

    -- App:run() goes through the HTTP channel, which fires on_request itself.
    eq(count_hook("on_request"), 1, "App:run() fires on_request exactly once")
end

----------------------------------------------------------------------
print(string.format("plugin hook tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("plugin hook tests passed")
