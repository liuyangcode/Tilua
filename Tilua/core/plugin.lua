--- Tilua.core.plugin
--- Plugin registry & hook bus for framework extensions
--- (OpenAPI, CLI, WebSocket, metrics, etc.)
---
--- Plugin shape:
---   {
---     name = "openapi",
---     priority = 100,           -- lower runs first on boot
---     register = function(app) end,  -- optional one-time setup
---     hooks = {
---       on_boot          = function(app) end,
---       on_route_loaded  = function(app, router) end,
---       on_worker_init   = function(app) end,
---       on_request       = function(ctx) end,   -- after set_by_lua
---       on_dispatch      = function(ctx, matched, rule) end,
---       on_response      = function(ctx) end,
---       on_error         = function(ctx, err) end,
---       on_shutdown      = function(app) end,
---     }
---   }

local Plugin = {
    _list = {},
    _by_name = {},
}

local HOOKS = {
    "on_boot",
    "on_route_loaded",
    "on_worker_init",
    "on_request",
    "on_dispatch",
    "on_response",
    "on_error",
    "on_shutdown",
}

function Plugin.reset()
    Plugin._list = {}
    Plugin._by_name = {}
end

--- Register a plugin table (idempotent by name)
function Plugin.register(plugin)
    assert(type(plugin) == "table", "plugin must be a table")
    assert(type(plugin.name) == "string" and plugin.name ~= "", "plugin.name required")
    if Plugin._by_name[plugin.name] then
        return Plugin._by_name[plugin.name]
    end
    plugin.priority = tonumber(plugin.priority) or 100
    plugin.hooks = plugin.hooks or {}
    Plugin._list[#Plugin._list + 1] = plugin
    Plugin._by_name[plugin.name] = plugin
    table.sort(Plugin._list, function(a, b)
        return a.priority < b.priority
    end)
    return plugin
end

function Plugin.get(name)
    return Plugin._by_name[name]
end

function Plugin.list()
    return Plugin._list
end

--- Fire a named hook across every registered plugin.
---
--- Argument contract (see docs/EXTENSIONS.md):
---
---   on_boot          (app)
---   on_route_loaded  (app, router)
---   on_worker_init   (app)
---   on_request       (app, ctx)
---   on_dispatch      (app, ctx, matched, router)
---   on_response      (app, ctx, response)
---   on_error         (app, ctx, exception)
---   on_shutdown      (app)
---
--- `app` is always the first argument because it exists in every phase (several
--- run before any request exists) and carries the container, so a hook can
--- resolve whatever it needs with `app:make(...)`.  `ctx` is the request scope
--- when there is one, and nil during boot.  `ctx:make(...)` reaches the same
--- services.
---
--- A throw inside a hook is caught and logged: one broken plugin must not take
--- down the request.
function Plugin.emit(hook, app, ctx, ...)
    for i = 1, #Plugin._list do
        local p = Plugin._list[i]
        local fn = p.hooks and p.hooks[hook]
        if type(fn) == "function" then
            local ok, err = pcall(fn, app, ctx, ...)
            if not ok then
                local log = app and app.logger
                    or (ctx and ctx.logger)
                    or (app and app.ctx and app.ctx.logger)
                if log and log.error then
                    log:error("plugin ", tostring(p.name), " hook ", hook,
                        " error: ", tostring(err))
                elseif ngx then
                    ngx.log(ngx.ERR, "plugin ", tostring(p.name), " hook ", hook,
                        " error: ", tostring(err))
                end
            end
        end
    end
end

--- Failures from the last `load_from_config`, for diagnostics.
Plugin._load_errors = {}

--- Load plugins from config.plugins = { "Tilua.openapi", "myapp.plugins.x", ... }
---
--- Reads the config through `app:make("config")` rather than `app.config`, so it
--- works whether it is called on the Application class (where a plain property
--- read does NOT resolve bindings — invariant 2 in the container) or on an
--- instance.
function Plugin.load_from_config(app)
    local cfg = app and app.config
    if cfg == nil and type(app.make) == "function" then
        local ok, resolved = pcall(app.make, app, "config")
        if ok then
            cfg = resolved
        end
    end

    local list = cfg and cfg.plugins
    if type(list) ~= "table" then
        return
    end
    for _, item in ipairs(list) do
        local mod
        if type(item) == "string" then
            -- Loud, not silent: a mistyped plugin path used to be swallowed by
            -- pcall(require) and the plugin simply never existed.
            local ok, m = pcall(require, item)
            if ok then
                mod = m
            else
                Plugin._load_errors[#Plugin._load_errors + 1] =
                    item .. ": " .. tostring(m):gsub("\n.*", "")
            end
        elseif type(item) == "table" then
            mod = item
        end
        if mod then
            if type(mod.new) == "function" then
                mod = mod.new(app)
            elseif type(mod) == "function" then
                mod = mod(app)
            end
            if mod then
                Plugin.register(mod)
                if type(mod.register) == "function" then
                    pcall(mod.register, app)
                end
            end
        end
    end
end

--- Call register() on all plugins then on_boot
function Plugin.boot(app)
    for i = 1, #Plugin._list do
        local p = Plugin._list[i]
        if type(p.register) == "function" and not p._registered then
            pcall(p.register, app)
            p._registered = true
        end
    end
    Plugin.emit("on_boot", app)
end

Plugin.HOOKS = HOOKS

return Plugin
