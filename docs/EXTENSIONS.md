# Tilua Extension Architecture

Framework hooks for **OpenAPI**, **CLI**, **WebSocket**, and custom plugins.

## Concepts

| Layer | Module | Role |
|-------|--------|------|
| Plugin bus | `Tilua.core.plugin` | Register hooks: boot, routes, request, response, error |
| Channel | `Tilua.core.channel` | Entry multiplex: HTTP / WebSocket / CLI |
| Stubs | `Tilua.openapi` / `Tilua.cli` / `Tilua.websocket` | Optional capabilities |

```
ngx content_by_lua → App:run() → Channel.dispatch()
                                      ├─ websocket (upgrade)
                                      ├─ cli (_channel=cli)
                                      └─ http (default) → router → dispatcher
```

## Enable plugins

```lua
-- config
plugins = {
  "Tilua.openapi",
  "Tilua.cli",
  "Tilua.websocket",
}
```

Or at runtime:

```lua
app:use(require("Tilua.openapi"))
```

## Hooks

```lua
app:use({
  name = "metrics",
  priority = 50,
  hooks = {
    on_boot = function(app) end,
    on_route_loaded = function(app, router) end,
    on_worker_init = function(app) end,
    on_request = function(ctx) end,
    on_dispatch = function(ctx, matched, rule) end,
    on_response = function(ctx) end,
    on_error = function(ctx, err) end,
  }
})
```

## OpenAPI

```lua
local OpenAPI = require("Tilua.openapi")
OpenAPI.document({
  path = "/api/users",
  method = "get",
  summary = "List users",
  tags = { "users" },
})
-- GET /openapi.json → OpenAPI.to_json()
```

## CLI

```bash
# after requiring app
lua -e 'require("Tilua.cli").run(require("myapp"), {"routes"})'
```

Built-ins: `routes`, `version`, `help`.

```lua
require("Tilua.cli").command("seed", function(app, args)
  -- ...
end, "Seed database")
```

## WebSocket

```lua
local WS = require("Tilua.websocket")
WS.on("/chat", function(wb, app)
  while true do
    local data, typ, err = wb:recv_frame()
    if not data then break end
    wb:send_text(data)
  end
end)
```

Or implement `function App:on_websocket(wb)`.

## Custom channel

```lua
app:channel({
  name = "grpc",
  priority = 40,
  match = function(app) return ngx.var.content_type == "application/grpc" end,
  handle = function(app) -- ... end,
})
```
