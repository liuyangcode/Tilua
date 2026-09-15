--- Tilua.core.channel
--- Entry-channel abstraction: HTTP / WebSocket / CLI share one App kernel.
---
--- Channel shape:
---   {
---     name = "http",
---     priority = 100,
---     --- return true if this channel should handle the current context
---     match = function(app) return true end,
---     --- handle request; return response or nil
---     handle = function(app) end,
---   }

local Channel = {
    _list = {},
    _by_name = {},
}

function Channel.reset()
    Channel._list = {}
    Channel._by_name = {}
end

function Channel.register(ch)
    assert(type(ch) == "table" and type(ch.name) == "string", "channel needs name")
    assert(type(ch.match) == "function" and type(ch.handle) == "function",
        "channel needs match() and handle()")
    if Channel._by_name[ch.name] then
        return Channel._by_name[ch.name]
    end
    ch.priority = tonumber(ch.priority) or 100
    Channel._list[#Channel._list + 1] = ch
    Channel._by_name[ch.name] = ch
    table.sort(Channel._list, function(a, b)
        return a.priority < b.priority
    end)
    return ch
end

function Channel.get(name)
    return Channel._by_name[name]
end

--- Pick first matching channel and run it
function Channel.dispatch(app)
    for i = 1, #Channel._list do
        local ch = Channel._list[i]
        local ok, matched = pcall(ch.match, app)
        if ok and matched then
            return ch.handle(app)
        end
    end
    return nil, "no channel matched"
end

-------------------------------------------------
-- Built-in HTTP channel (default)
-------------------------------------------------

local function http_match(app)
    -- WebSocket upgrade is handled by ws channel (higher priority)
    local upgrade = ngx and ngx.var and ngx.var.http_upgrade
    if upgrade and string.lower(upgrade) == "websocket" then
        return false
    end
    return true
end

local function http_handle(app)
    local Plugin = require("Tilua.core.plugin")
    Plugin.emit("on_request", app)

    local path = app.config and app.config.health_path or "/health"
    local uri = (app.request and app.request.path_info) or (ngx and ngx.var.uri) or ""
    if uri == path or uri == path .. "/" then
        local body = '{"status":"ok","app":"' .. (app.name or "tilua") ..
            '","channel":"http","pid":' .. tostring(ngx.worker.pid()) .. "}"
        local resp = app.response
        if resp then
            resp.status = 200
            resp.headers = resp.headers or {}
            resp.headers["Content-Type"] = "application/json; charset=utf-8"
            resp.body = body
        end
        Plugin.emit("on_response", app)
        return resp
    end

    local matched, router = app.route.run(app)
    Plugin.emit("on_dispatch", app, matched, router)
    local result = app.dispatcher:run(matched, router)
    Plugin.emit("on_response", app)
    return result
end

Channel.register({
    name = "http",
    priority = 100,
    match = http_match,
    handle = http_handle,
})

-------------------------------------------------
-- Built-in WebSocket channel (stub – ready for implementation)
-------------------------------------------------

local function ws_match(app)
    local upgrade = ngx and ngx.var and ngx.var.http_upgrade
    return upgrade and string.lower(upgrade) == "websocket"
end

local function ws_handle(app)
    local Plugin = require("Tilua.core.plugin")
    Plugin.emit("on_request", app)
    -- Prefer app-level or plugin handler
    if type(app.on_websocket) == "function" then
        return app:on_websocket()
    end
    local ws_plugin = Plugin.get("websocket")
    if ws_plugin and type(ws_plugin.handle) == "function" then
        return ws_plugin.handle(app)
    end
    -- Stub: reject if no handler
    if app.response then
        app.response.status = 501
        app.response.body = "WebSocket handler not implemented"
    end
    if ngx and ngx.status then
        ngx.status = 501
        ngx.say("WebSocket handler not implemented; register Tilua.websocket or app:on_websocket")
        ngx.exit(501)
    end
    return app.response
end

Channel.register({
    name = "websocket",
    priority = 50, -- before HTTP
    match = ws_match,
    handle = ws_handle,
})

-------------------------------------------------
-- Built-in CLI channel (stub – no ngx HTTP context)
-------------------------------------------------

local function cli_match(app)
    return app._channel == "cli" or (not ngx) or (ngx and ngx.config and ngx.config.subsystem == nil and app._cli)
end

local function cli_handle(app)
    local Plugin = require("Tilua.core.plugin")
    if type(app.on_cli) == "function" then
        return app:on_cli(app._cli_args or {})
    end
    local cli_plugin = Plugin.get("cli")
    if cli_plugin and type(cli_plugin.handle) == "function" then
        return cli_plugin.handle(app, app._cli_args or {})
    end
    return nil, "CLI handler not registered"
end

Channel.register({
    name = "cli",
    priority = 10,
    match = cli_match,
    handle = cli_handle,
})

return Channel
