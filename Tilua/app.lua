--- Tilua.app
--- The application object *is* an IoC container.
---
--- `App` derives from `Tilua.core.container`, so every service the framework
--- offers is a container binding rather than a bespoke lazy getter.  The old
--- `App:get_*` methods are kept as thin wrappers so existing code keeps working.
---
--- Service lifetimes
---   singleton (worker scope)  : config, logger, middleware, router, dispatcher,
---                               view_engine, plugin bus
---   scoped    (request scope) : request, response, view, cache, db, model,
---                               service, session
---   per resolve               : anything the app binds itself
---
--- Scoped services are released by `App:flush()` at the end of the request,
--- which replaces the old `on_app_handled_callbacks` list.

local Container = require("Tilua.core.container")
local lw_utils  = require("Tilua.utils.util")
local path      = require("Tilua.utils.path")

local import  = lw_utils.import
local combine = lw_utils.extend
local bind1   = lw_utils.bind1

local lifecycle = require("Tilua.core.lifecycle")

---@class app : container
local App = Container.define()

-----------------------------------------------------------------------
-- container wiring
-----------------------------------------------------------------------

--- Register the framework's own services.
--- Applications may `bind`/`singleton`/`scoped` over any of these names.
---
--- Every factory takes the resolving container as its first argument.  Use
--- that (`c`) rather than closing over `self`: the phase handlers run on the
--- Application *class*, while `register_default_bindings` may have been called
--- on an instance, and only the resolver knows which one is in play.
function App:register_default_bindings()
    -- Instances created without opts clear `_loader`; restore it so class-like
    -- resolution keeps working for both the class and request contexts.
    if rawget(self, "_loader") == nil then
        rawset(self, "_loader", import)
    end

    -- worker-scoped ------------------------------------------------

    -- Configuration is a singleton resolved lazily: the first access loads the
    -- layered config, so `app.config` works without an explicit boot step.
    self:singleton("config", function(c)
        return c:ensure_config()
    end)

    self:singleton("logger", function(c)
        local log_mod = import("Tilua.log")
        local cfg = c.config or {}
        if log_mod and log_mod.new then
            return log_mod.new(cfg.log or {})
        end
        return log_mod
    end)

    self:singleton("middleware", function(c)
        return require("Tilua.middleware")(c)
    end)

    -- Plugin bus. Registered as a container singleton so lifecycle code and
    -- applications reach the same registry instead of require()-ing the
    -- module directly at every call site.
    self:singleton("plugin", function()
        return require("Tilua.core.plugin")
    end)

    -- Entry-channel multiplexer (HTTP / WebSocket / CLI). Also module-global;
    -- exposed through the container for the same reason.
    self:singleton("channel", function()
        return require("Tilua.core.channel")
    end)

    self:singleton("router", function(c)
        local route = require("Tilua.http.router")
        if not c.name or c.name == "" then
            error("container: App.name must be set before the router can be built", 0)
        end
        route.set_app_name(c.name)
        return route
    end)

    self:singleton("dispatcher", function(c)
        local name = (c.config and c.config.dispatch) or "Tilua.http.dispatcher"
        local Dispatch = import(name)
        if not (Dispatch and Dispatch.run) then
            error("container: dispatcher '" .. tostring(name) .. "' must expose run()", 0)
        end
        return Dispatch(c)
    end)

    self:singleton("view_engine", function(c)
        local root = c.path
        if not root then
            error("container: view_engine requires config (app.path) to be loaded", 0)
        end
        return lifecycle.init_view_engine(root)
    end)

    -- request-scoped -----------------------------------------------

    self:scoped("request", function(c)
        return import("Tilua.http.request").capture(c)
    end)

    self:scoped("response", function(c)
        return import("Tilua.http.response")(c)
    end)

    self:scoped("view", function(c)
        return import("Tilua.view")(c)
    end)

    self:scoped("cache", function(c)
        return require("Tilua.cache")(c.config, c.logger)
    end)

    self:scoped("db", function(c)
        return require("Tilua.db")({
            ctx    = c.config,
            logger = c.logger,
        })
    end)

    self:scoped("model", function(c)
        return require("Tilua.model")(c)
    end)

    self:scoped("service", function(c)
        return require("Tilua.service")(c)
    end)

    return self
end

-----------------------------------------------------------------------
-- accessors
-----------------------------------------------------------------------

--- Resolve a service or raise. Use when the service must exist.
function App:service_or_fail(name)
    if not self:bound(name) then
        error("container: service '" .. tostring(name) .. "' is not bound", 2)
    end
    return self:make(name)
end

--- Hostname of the app; also the marker used for boot detection.
local function config_combine(dest, src)
    if type(src) == "table" then
        combine(dest, src)
    end
    return dest
end

--- Load the layered configuration once per worker.
--- 1. Tilua.config.default  2. <App>.config.default  3. <App>.config.<status>
function App:ensure_config()
    local existing = self._instances["config"]
    if existing then
        return existing
    end
    -- guard against re-entrancy: the `config` binding calls this function
    if self._config_loading then
        error("container: config resolution is re-entrant", 2)
    end
    self._config_loading = true

    local cfg = {}
    config_combine(cfg, import("Tilua.config.default"))

    local appname = self.name
    if not appname or appname == "" then
        error("container: App.name must be set before the config can be loaded", 2)
    end

    self.path = path.get_module_path(appname, "app")
    config_combine(cfg, import(appname, "config", "default"))
    if self.status then
        config_combine(cfg, import(appname, "config", self.status))
    end

    -- log path is resolved relative to the app root
    cfg.log = cfg.log or {}
    if not cfg.log.path or not cfg.log.absolute then
        cfg.log.path = path.join(self.path, cfg.log.path or "log")
    end

    self:instance("config", cfg)
    self._config_loading = false
    return cfg
end

--- Does any ancestor already own framework bindings?
--- Request contexts should delegate to the Application class so that
--- worker-scoped singletons are shared instead of rebuilt per request.
local function ancestor_has_bindings(c)
    local seen = {}
    local p = rawget(c, "_parent")
    while p ~= nil and not seen[p] do
        seen[p] = true
        if rawget(p, "_bindings_registered") then
            return true
        end
        p = rawget(p, "_parent")
    end
    return false
end

--- Ensure this container (class or instance) is wired: container tables, a
--- loader, and the framework bindings.  A subclass created via `App.define()`
--- has not been through `_boot_container`, yet the phase handlers are invoked
--- on the class, so this must be idempotent and safe on both.
function App:ensure_container_ready()
    if rawget(self, "_bindings") == nil then
        self:initialize()
    end
    if rawget(self, "_loader") == nil then
        rawset(self, "_loader", import)
    end
    if not rawget(self, "_bindings_registered") and not ancestor_has_bindings(self) then
        rawset(self, "_bindings_registered", true)
        self:register_default_bindings()
    end
    return self
end

--- Master-phase setup (init_by_lua): load the layered config and register the
--- route rules.  Nothing here touches the filesystem or per-worker state, so a
--- broken config or route rule fails `nginx -t` / reload instead of the first
--- request.  Idempotent.
function App:load_config_and_routes()
    self:ensure_container_ready()
    local cfg = self:ensure_config()

    -- The routes module commonly registers its rules at *require* time
    -- (`route.get(...)` at file scope), so the app name must be established
    -- before it is loaded.  Resolving the router singleton does that via
    -- set_app_name().
    local router = self:make("router")

    local appname = self.name
    local routes = import(appname .. ".routes")
    if type(routes) == "function" then
        routes(self, router)
    end
    router.init_rule_caches(cfg.route or {})

    self:make("plugin").emit("on_route_loaded", self, router)
    return self
end

--- Alias kept for callers that used the old single-phase boot.
function App:register_routes()
    return self:load_config_and_routes()
end

--- Worker-phase setup (init_worker_by_lua): view engine, middleware config,
--- plugins.  Needs the filesystem and per-worker state, so it must not run in
--- the master process.  Idempotent.
function App:boot_worker()
    if self._worker_booted then
        return self
    end

    self:ensure_container_ready()
    local cfg = self:ensure_config()

    -- middleware manager needs the alias / group / phase configuration
    local mw = self:make("middleware")
    if mw and mw.load then
        mw.load(cfg)
    end

    -- view engine (creates cache dirs) + template caching policy.
    -- `caching` is a colon method; a dot call would pass the flag as `self`.
    local engine = self:make("view_engine")
    if engine and engine.template and engine.template.caching then
        engine.template:caching(not self.debug)
    end

    local plugins = self:make("plugin")
    plugins.load_from_config(self)
    plugins.boot(self)

    self._worker_booted = true
    return self
end

--- Both phases at once.  Useful for CLI / tests / non-nginx embedding where the
--- master/worker split does not apply.
function App:boot()
    self:load_config_and_routes()
    self:boot_worker()
    return self
end

-----------------------------------------------------------------------
-- lifecycle (delegated to Tilua.core.lifecycle)
-----------------------------------------------------------------------

App.init_by_lua        = lifecycle.init_by_lua
App.is_inited_by_lua   = lifecycle.is_inited_by_lua
App.init_worker_by_lua = lifecycle.init_worker_by_lua
App.rewrite_by_lua     = lifecycle.rewrite_by_lua
App.access_by_lua      = lifecycle.access_by_lua
App.content_by_lua     = lifecycle.content_by_lua
App.log_by_lua         = lifecycle.log_by_lua

--- Kept for compatibility with older example code.
function App:is_app_inited()
    return self:is_inited_by_lua()
end

-----------------------------------------------------------------------
-- backward-compatible getters (thin wrappers over the container)
-----------------------------------------------------------------------

function App:get_config(key)
    local cfg = self:make("config")
    if key then
        return lw_utils.index_value(cfg, key)
    end
    return cfg
end

function App:get_logger()  return self:make("logger") end
function App:get_view()    return self:make("view") end
function App:get_cache()   return self:make("cache") end
function App:get_db()      return self:make("db") end
function App:get_model()   return self:make("model") end
function App:get_service() return self:make("service") end
function App:get_request() return self:make("request") end
function App:get_response() return self:make("response") end
function App:get_dispatcher() return self:make("dispatcher") end

-----------------------------------------------------------------------
-- compatibility: app-handled callbacks
-----------------------------------------------------------------------

--- The container owns teardown now, but keep the old registration API so
--- existing apps keep working.  Callbacks run after scoped services are
--- released, in registration order, mirroring the old behaviour.
function App:on_app_handled(cb)
    if type(cb) ~= "function" then
        error("on_app_handled expects a function", 2)
    end
    self._handled[#self._handled + 1] = cb
    return cb
end

-----------------------------------------------------------------------
-- plugins / channels
-----------------------------------------------------------------------

--- Register a framework plugin (OpenAPI / CLI / WebSocket / custom).
---
--- NOTE: `Plugin.register` / `Channel.register` / `Plugin.get` are *dot*
--- functions, not methods.  Calling them with `:` would bind the bus as the
--- first argument and silently shift the real one.  `plugin`, `channel`,
--- `router`, `middleware` and `config` also collide with method names on the
--- class chain, which wins over bindings — so make() is used explicitly.
function App:use(plugin)
    return self:make("plugin").register(plugin)
end

--- Register an entry channel (http / websocket / cli / custom).
function App:use_channel(ch)
    return self:make("channel").register(ch)
end

--- Look up a registered plugin by name.
function App:get_plugin(name)
    return self:make("plugin").get(name)
end

function App:unpack()
    return self:make("request"), self:make("response"),
           self:make("cache"), self:make("config")
end

-----------------------------------------------------------------------
-- request teardown
-----------------------------------------------------------------------

--- Release every request-scoped service and run registered callbacks.
--- Called from log_by_lua; safe to call more than once.
function App:flush_scope()
    local released, err = self:flush()

    local handled = self._handled or {}
    for i = 1, #handled do
        local ok, cerr = pcall(handled[i])
        if not ok then
            err = err and (err .. "; handled -> " .. tostring(cerr))
                       or ("handled -> " .. tostring(cerr))
        end
    end
    self._handled = {}

    local logger = self:make("logger")
    if err and logger and logger.error then
        pcall(function()
            logger:error("container flush: ", err)
        end)
    end

    return released, err
end

-----------------------------------------------------------------------
-- runtime entry points
-----------------------------------------------------------------------

--- Main entry used by content_by_lua_block (and CLI/WS via Channel).
function App:run()
    local result, err = self:make("channel").dispatch(self)
    if result ~= nil then
        return result
    end
    -- Fallback: classic HTTP path (if no channel claimed the request).
    --
    -- NOTE: this is the non-phase entry point.  Under a normal nginx config the
    -- lifecycle handlers run instead and fire these hooks themselves; wiring the
    -- hooks here as well would double-fire them, so the phase path is the one
    -- that owns `on_request` / `on_dispatch` / `on_response` / `on_error`.
    local logger = self:make("logger")
    if logger and logger.error then
        logger:error("channel dispatch: ", err or "nil", " - fallback HTTP")
    end
    local plugins = self:make("plugin")
    local matched, router = self:make("router").run(self)
    plugins.emit("on_dispatch", self, nil, matched, router)
    local out = self:make("dispatcher"):run(matched, router)
    plugins.emit("on_response", self, nil, out)
    return out
end

--- Explicit CLI entry (no HTTP context).
function App:run_cli(args)
    self._channel = "cli"
    self._cli = true
    self._cli_args = args or {}
    return self:make("channel").dispatch(self)
end

--- Instance state that is *not* part of the container.
--- Called explicitly by `App()` so the container is initialised first.
function App:setup_context()
    self._handled  = self._handled or {}
    self._deferred = self._deferred or {}
    return self
end

-----------------------------------------------------------------------
-- constructor
-----------------------------------------------------------------------

--- Constructor hook invoked by Container._construct for every instance.
--- Runs regardless of what a subclass does in `_construct`, which is what
--- makes `App:name()`, `app.db` and the legacy getters work in subclasses.
--- Deliberately does no eager work: `name` / `status` / `debug` are usually
--- assigned by the application module *after* the first instance exists, so
--- everything that needs them stays lazy (the factories above are).
function App:_boot_container()
    if self._container_booted then
        return self
    end
    self._container_booted = true
    self:setup_context()
    return self:ensure_container_ready()
end

--- Instance property resolver, kept for callers that look it up on the class.
--- The class chain is already exhausted by the container's `__index`, so this
--- only needs to consult the bindings.
function App.resolve_instance_property(self, name)
    return self:resolve_property(name)
end

--- The Application *class* is itself a container: the OpenResty phase handlers
--- (`App:init_by_lua`, `App:rewrite_by_lua`, …) are invoked on the class, and
--- resolve config/logger/router/plugin from it.  Initialize it here so those
--- methods have container state before any instance exists.
App:initialize()
App._loader = import
App:setup_context()
App:ensure_container_ready()

return App
