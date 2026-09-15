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

--- Fire a named hook across all plugins (and optional app method)
function Plugin.emit(hook, app_or_ctx, ...)
    for i = 1, #Plugin._list do
        local p = Plugin._list[i]
        local fn = p.hooks and p.hooks[hook]
        if type(fn) == "function" then
            local ok, err = pcall(fn, app_or_ctx, ...)
            if not ok then
                local log = app_or_ctx and (app_or_ctx.logger or (app_or_ctx.ctx and app_or_ctx.ctx.logger))
                if log and log.error then
                    log:error("plugin ", p.name, " hook ", hook, " error: ", err)
                elseif ngx then
                    ngx.log(ngx.ERR, "plugin ", p.name, " hook ", hook, " error: ", tostring(err))
                end
            end
        end
    end
end

--- Load plugins from config.plugins = { "Tilua.openapi", "myapp.plugins.x", ... }
function Plugin.load_from_config(app)
    local list = app.config and app.config.plugins
    if type(list) ~= "table" then
        return
    end
    for _, item in ipairs(list) do
        local mod
        if type(item) == "string" then
            local ok, m = pcall(require, item)
            if ok then mod = m end
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
