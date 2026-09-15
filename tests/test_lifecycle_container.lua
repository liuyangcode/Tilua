--- Lifecycle integration: drives the real OpenResty phase handlers and checks
--- that the request scope is created per request, shared correctly with the
--- worker container, and released at log_by_lua.
--- Run: luajit tests/support/lua_stub.lua tests/test_lifecycle_container.lua

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

local RequestCtx = require("Tilua.core.request")

---------------------------------------------------------------
-- 1. init_by_lua (master) loads config + route rules only
---------------------------------------------------------------
local App = require("TestApp.app")

ok(App.pid == nil, "worker state starts uninitialised")
ok(not App:is_inited_by_lua(), "is_inited_by_lua is false before init_worker")
ok(App._master_booted == nil, "master not booted yet")

App:init_by_lua()

eq(App._master_booted, true, "init_by_lua marked the master booted")
ok(App:make("config") ~= nil, "config resolved during master boot")
ok(App._worker_booted == nil, "init_by_lua must NOT do worker-only work")

--- the master boot must not require a view engine (no filesystem work)
ok(pcall(function() return App:make("config") end), "config is reachable")

---------------------------------------------------------------
-- 2. init_worker_by_lua does worker-only setup
---------------------------------------------------------------
App:init_worker_by_lua()

eq(App._worker_booted, true, "init_worker_by_lua marked the worker booted")
eq(App.pid, ngx.worker.pid(), "init_worker_by_lua recorded the worker pid")
ok(App:is_inited_by_lua(), "is_inited_by_lua is true after init_worker")
ok(App:make("view_engine") ~= nil, "view engine built in the worker phase")

local cfg = App:make("config")
local router = App:make("router")
local caches = router.get_route_caches and router.get_route_caches("TestApp")
ok(type(caches) == "table" and #caches >= 1, "fixture routes registered")

--- both phases are idempotent
App:init_by_lua()
App:init_worker_by_lua()
eq(App:make("config"), cfg, "config is not rebuilt by a second boot")
eq(App:make("router"), router, "router is not rebuilt by a second boot")

---------------------------------------------------------------
-- 3. rewrite_by_lua creates the request scope
---------------------------------------------------------------
ngx.var.uri = "/greeter"
ngx.var.request_method = "GET"
ngx.ctx = {}          -- fresh request shell

ok(RequestCtx.slot() == nil, "no request slot before rewrite")

App:rewrite_by_lua()

local slot = RequestCtx.slot()
ok(slot ~= nil, "rewrite_by_lua created the request slot")
ok(slot.ctx ~= nil, "slot holds a container context")
ok(slot.uri == "/greeter", "slot records the request uri fingerprint")
eq(slot.flushed, false, "slot starts unflushed")

local ctx = slot.ctx
ok(ctx ~= App, "the request context is a distinct instance")
ok(rawget(ctx, "_parent") == App, "request context is parented to the worker class")
ok(ctx:make("config") == cfg, "request shares the worker config singleton")
ok(ctx:make("router") == router, "request shares the worker router singleton")
eq(ctx:make("plugin"), App:make("plugin"), "request shares the plugin bus")

---------------------------------------------------------------
-- 4. the slot is reused within the same request
---------------------------------------------------------------
local ctx_again = RequestCtx.context(App, { scope = "access" })
ok(ctx_again == ctx, "re-entering the scope returns the same context")

---------------------------------------------------------------
-- 5. an internal redirect starts a fresh scope
---------------------------------------------------------------
-- Populate the scope first so the checks below are meaningful.
local req_before_redirect = ctx:make("request")
ok(#ctx:scoped_instances() >= 1, "old scope had scoped services before redirect")

ngx.ctx = {}                       -- nginx replaced the shell
ngx.var.uri = "/greeter-redirected"

local redirected = RequestCtx.context(App, { scope = "content" })
ok(redirected ~= ctx, "internal redirect produced a NEW request context")

--- KNOWN LIMITATION: on an internal redirect OpenResty replaces `ngx.ctx`
--- wholesale, so the pre-redirect context is no longer reachable from it and
--- cannot be released here — `slot.uri ~= uri` only fires when the slot
--- survives, which is not the case after `ngx.exec`.  The old scope is instead
--- reclaimed by normal GC once the request ends.  Releasing it eagerly would
--- require keeping a module-level reference to the previous context, which is
--- itself a cross-request leak risk; tracked as a follow-up.
ok(#redirected:scoped_instances() == 0,
    "the redirected scope starts empty (old scope is not released eagerly)")

---------------------------------------------------------------
-- 6. scoped services live on the request, not the worker
---------------------------------------------------------------
eq(#redirected:scoped_instances(), 0, "new scope starts empty")

local req = redirected:make("request")
ok(req ~= nil, "request service resolves in the request scope")
ok(#redirected:scoped_instances() >= 1, "request is tracked as scoped")
eq(#App:scoped_instances(), 0, "worker scope holds no scoped services")

local resp = redirected:make("response")
ok(resp.ctx == redirected, "response is bound to the request context")

---------------------------------------------------------------
-- 7. log_by_lua releases exactly the request scope, once
---------------------------------------------------------------
ok(#redirected:scoped_instances() >= 2, "services live before flush")

App:log_by_lua()

eq(#redirected:scoped_instances(), 0, "log_by_lua released the request scope")
eq(RequestCtx.slot().flushed, true, "slot marked flushed")

--- worker singletons survive
eq(App:make("config"), cfg, "config survived the request")
eq(App:make("router"), router, "router survived the request")

--- a second log_by_lua in the same request must be a no-op
local released_again = RequestCtx.finish(App)
eq(released_again, 0, "second flush in the same request released nothing")

---------------------------------------------------------------
-- 8. a new request gets a brand new scope
---------------------------------------------------------------
ngx.ctx = {}
ngx.var.uri = "/greeter"

App:rewrite_by_lua()

local slot2 = RequestCtx.slot()
ok(slot2.ctx ~= ctx, "second request builds a new context")
ok(slot2.ctx ~= redirected, "second request is not the redirected context")

--- rewrite_by_lua resolves the route, which creates the scoped `request`
--- service, so the scope is no longer empty at this point — but it must hold
--- only THIS request's services.
local req2 = slot2.ctx:make("request")
ok(req2 ~= req, "second request has its own request object")
ok(#slot2.ctx:scoped_instances() >= 1, "second request has its own scoped services")

App:log_by_lua()
eq(#slot2.ctx:scoped_instances(), 0, "second request flushed cleanly")

---------------------------------------------------------------
-- 9. removing set_by_lua: the phase API must not expose it
---------------------------------------------------------------
ok(App.set_by_lua == nil, "App.set_by_lua was removed")
ok(App.is_setted_by_lua == nil, "App.is_setted_by_lua was removed")
ok(type(App.rewrite_by_lua) == "function", "rewrite_by_lua is the entry point")
ok(type(App.access_by_lua) == "function", "access_by_lua is exposed")
ok(type(App.content_by_lua) == "function", "content_by_lua is exposed")

---------------------------------------------------------------
print(string.format("lifecycle container tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("lifecycle container tests passed")
