--- Tilua.websocket (interface stub)
--- WebSocket channel handler using resty.websocket when available.
---
--- Enable: config.plugins = { "Tilua.websocket" }
--- Or implement app:on_websocket()

local WS = {
    name = "websocket",
    priority = 70,
    _handlers = {}, -- path -> function(wb, app)
}

function WS.new(app)
    return WS
end

function WS.register(app)
    -- optional route helper
end

--- Register path handler: WS.on("/chat", function(wb, app) ... end)
function WS.on(path, handler)
    WS._handlers[path] = handler
end

function WS.handle(app)
    local ok, server = pcall(require, "resty.websocket.server")
    if not ok or not server then
        ngx.status = 501
        ngx.say("resty.websocket.server not available")
        return ngx.exit(501)
    end

    local wb, err = server:new({
        timeout = (app.config and app.config.ws_timeout) or 5000,
        max_payload_len = (app.config and app.config.ws_max_payload) or 65535,
    })
    if not wb then
        ngx.log(ngx.ERR, "websocket handshake failed: ", err)
        return ngx.exit(444)
    end

    local path = (app.request and app.request.path_info) or ngx.var.uri or "/"
    local handler = WS._handlers[path]
    if not handler and type(app.on_websocket) == "function" then
        return app:on_websocket(wb)
    end
    if not handler then
        wb:send_close(1000, "no handler")
        return
    end

    local ok2, err2 = pcall(handler, wb, app)
    if not ok2 then
        ngx.log(ngx.ERR, "websocket handler error: ", err2)
        pcall(function()
            wb:send_close(1011, "internal error")
        end)
    end
end

WS.hooks = {
    on_boot = function(app)
        if app.logger and app.logger.debug then
            app.logger:debug("WebSocket plugin ready; use Tilua.websocket.on(path, handler)")
        end
    end,
}

return WS
