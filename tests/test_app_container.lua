--- Container integration tests for the Application object.
--- Run:
---   luajit tests/support/lua_stub.lua tests/test_app_container.lua
---   docker run --rm -v <repo>:/app -w /app openresty/openresty:1.21.4.1-buster \
---          luajit tests/support/lua_stub.lua tests/test_app_container.lua

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

local function is_table(v, label)
    checks = checks + 1
    if type(v) ~= "table" then
        failures = failures + 1
        io.stderr:write("FAIL: " .. label .. " (got " .. type(v) .. ")\n")
    end
end

---------------------------------------------------------------
-- 1. the app class is a container
---------------------------------------------------------------
local App = require("TestApp.app")

ok(type(App.make) == "function", "TestApp inherits Container:make")
ok(type(App.singleton) == "function", "TestApp inherits Container:singleton")
ok(type(App.scoped) == "function", "TestApp inherits Container:scoped")
ok(type(App.flush) == "function", "TestApp inherits Container:flush")
ok(type(App.boot) == "function", "TestApp inherits App.boot()")
ok(type(App.flush_scope) == "function", "TestApp inherits App.flush_scope()")
ok(type(App.define) == "function", "TestApp can be subclassed further")
ok(App.__parent ~= nil, "TestApp records its parent class")

--- The class table is not an instance: instances are what resolve services.
local app = App()
ok(type(app) == "table", "App() builds an instance")
ok(type(app.make) == "function", "instance resolves container methods")
ok(type(app.boot) == "function", "instance resolves subclass methods")

---------------------------------------------------------------
-- 2. configuration resolves through the container
---------------------------------------------------------------
local cfg = app.config
is_table(cfg, "app.config resolves to a table")
eq(cfg.app_title, "Container Demo", "app config layer overrides defaults")
eq(cfg.health_path, "/healthz", "app config overrides framework default")
ok(cfg.default_charset ~= nil, "framework defaults are merged in")
ok(cfg.multipart ~= nil, "nested framework defaults are present")

---------------------------------------------------------------
-- 3. app-owned services, aliases and cross-binding resolution
---------------------------------------------------------------
local greeter = app.greeter
is_table(greeter, "app-registered service resolves")
eq(greeter.greet(), "hello Container Demo", "service may resolve other bindings")
ok(app.greeter == greeter, "app service is a singleton")
ok(app:make("hello") == greeter, "alias resolves to the same singleton")
eq(app:alias_of("hello"), "greeter", "alias_of reports the target")

---------------------------------------------------------------
-- 4. worker-scoped singletons are stable
---------------------------------------------------------------
ok(app.logger ~= nil, "logger singleton resolves")
ok(app.logger == app.logger, "logger is a singleton")

--- `router`, `middleware`, `plugin`, `channel` and `config` are *also* method
--- names on the class chain (App:router(), Container:config(), …).  The class
--- chain must win, otherwise `app:make()` / `app:boot()` would stop being
--- callable.  So those bindings are reached with make(), or a get_* wrapper.
--- Non-colliding bindings (`db`, `cache`, `logger`, …) support property syntax.
ok(app:make("router") ~= nil, "router singleton resolves")
ok(app:make("router") == app:make("router"), "router is a singleton")
ok(app:make("middleware") ~= nil, "middleware manager singleton resolves")
ok(app:make("middleware") == app:make("middleware"), "middleware manager is a singleton")
ok(app:make("config") == cfg, "config binding is the loaded config")

ok(app:make("dispatcher") ~= nil, "dispatcher singleton resolves")
ok(app:make("dispatcher") == app:make("dispatcher"), "dispatcher is a singleton")

--- The plugin bus and channel multiplexer are module-global registries; they
--- must be reachable through the container like every other singleton.
ok(app:make("plugin") ~= nil, "plugin bus resolves as a singleton")
ok(app:make("plugin") == app:make("plugin"), "plugin bus is a singleton")
eq(app:make("plugin"), require("Tilua.core.plugin"), "plugin bus is the canonical module")
eq(app:get_plugin("openapi"), nil, "get_plugin() looks up by name")

ok(app:make("channel") ~= nil, "channel multiplexer resolves as a singleton")
eq(app:make("channel"), require("Tilua.core.channel"), "channel is the canonical module")
ok(type(app:make("channel").dispatch) == "function", "channel exposes dispatch()")

--- `use` / `use_channel` must register through those same registries.
local probe = { name = "container-test-probe" }
local use_ok, use_res = pcall(function()
    return app:use(probe)
end)
ok(use_ok, "App:use(probe) did not raise (" .. tostring(use_res) .. ")")
eq(use_res, probe, "App:use registers on the plugin bus")
eq(app:get_plugin("container-test-probe"), probe, "registered plugin is retrievable")

local fake_channel = {
    name = "container-test-channel",
    match = function() return false end,
    handle = function() return nil end,
}
local ch_ok, ch_res = pcall(function()
    return app:use_channel(fake_channel)
end)
ok(ch_ok, "App:use_channel did not raise (" .. tostring(ch_res) .. ")")
eq(ch_res, fake_channel, "App:use_channel registers a channel")
eq(app:make("channel").get("container-test-channel"), fake_channel, "channel is retrievable")

---------------------------------------------------------------
-- 5. request-scoped services are stable inside a scope
---------------------------------------------------------------
local req1 = app.request
is_table(req1, "request resolves")
ok(req1 == app.request, "request is stable within a scope")

local resp1 = app.response
is_table(resp1, "response resolves")
ok(resp1.ctx == app, "response is bound to the app context")

local view1 = app.view
is_table(view1, "view resolves")

ok(#app:scoped_instances() >= 3, "scoped services are tracked")

---------------------------------------------------------------
-- 6. flush releases the scope but keeps bindings
---------------------------------------------------------------
local tracked = #app:scoped_instances()
local released = app:flush()
ok(released >= 3, "flush reports released scoped services")
eq(#app:scoped_instances(), 0, "no scoped services remain after flush")
ok(tracked >= released, "flush released at most what was tracked")

ok(app:bound("request"), "binding survives flush")
ok(app:bound("db"), "db binding survives flush")
ok(app:bound("cache"), "cache binding survives flush")

local req2 = app.request
ok(req2 ~= req1, "a new scope builds a new request instance")
ok(app.logger ~= nil and app.logger == app.logger, "singletons survive flush")

---------------------------------------------------------------
-- 7. flush_scope runs app-handled callbacks exactly once
---------------------------------------------------------------
local called = 0
app:on_app_handled(function()
    called = called + 1
end)
local forced = app.request   -- force a scoped service into existence
ok(forced ~= nil, "scoped service resolvable before flush_scope")
app:flush_scope()
eq(called, 1, "on_app_handled callback ran during flush_scope")

app:flush_scope()
eq(called, 1, "handled callbacks are not re-run on a second flush")

---------------------------------------------------------------
-- 8. defer is LIFO and flushed with the scope
---------------------------------------------------------------
local order = {}
app:defer(function() order[#order + 1] = "a" end)
app:defer(function() order[#order + 1] = "b" end)
app:flush_scope()
eq(#order, 2, "both deferred callbacks ran")
eq(order[1], "b", "defer is LIFO")

---------------------------------------------------------------
-- 9. flush tolerates a failing close()
---------------------------------------------------------------
app:scoped("broken", function()
    return {
        close = function()
            error("close exploded")
        end,
    }
end)
local broken = app.broken
ok(broken ~= nil, "custom scoped binding resolves")
local rel, err = app:flush()
ok(rel >= 1, "flush still released entries")
ok(err ~= nil and tostring(err):find("broken", 1, true) ~= nil,
    "flush reports the failing service in its error")
eq(#app:scoped_instances(), 0, "scope is empty even after a failing close()")

---------------------------------------------------------------
-- 10. legacy getters still work through the container
---------------------------------------------------------------
eq(app:get_config("app_title"), "Container Demo", "get_config('key') path works")
ok(app:get_config() == app.config, "get_config() returns the whole config")
ok(app:get_logger() == app.logger, "get_logger wraps the container")
ok(app:get_response() == app.response, "get_response wraps the scoped response")
ok(app:get_dispatcher() == app.dispatcher, "get_dispatcher wraps the singleton")
ok(app:get_service() == app.service, "get_service wraps the container")
ok(app:get_model() == app.model, "get_model wraps the container")

---------------------------------------------------------------
-- 11. unpack() still exposes request/response/cache/config
---------------------------------------------------------------
local ureq, uresp, ucache, ucfg = app:unpack()
ok(ureq == app.request, "unpack returns the request first")
ok(uresp == app.response, "unpack returns the response second")
ok(ucfg == app.config, "unpack returns the config fourth")

---------------------------------------------------------------
-- 12. boot() and config loading are idempotent
---------------------------------------------------------------
local cfg_before = app.config
app:boot()
app:boot()
ok(app.config == cfg_before, "boot does not rebuild the config")
ok(app._worker_booted == true, "boot marks the worker booted")

app:ensure_config()
ok(app.config == cfg_before, "ensure_config is idempotent")

---------------------------------------------------------------
-- 13. routes were registered during boot
---------------------------------------------------------------
ok(app:bound("router"), "router is bound after boot")
local caches = app.router.get_route_caches and app.router.get_route_caches("TestApp")
ok(type(caches) == "table", "route cache exists for TestApp")
ok(#caches >= 1, "fixture routes were registered during boot")

---------------------------------------------------------------
print(string.format("app container tests: %d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("app container tests passed")
