# Tilua Extension Architecture

Framework hooks for **OpenAPI**, **CLI**, **WebSocket**, and custom plugins.

## Concepts

| Layer | Module | Role |
|-------|--------|------|
| Plugin bus | `Tilua.core.plugin` | Register hooks: boot, routes, request, response, error |
| Channel | `Tilua.core.channel` | Entry multiplex: HTTP / WebSocket / CLI |
| Stubs | `Tilua.openapi` / `Tilua.cli` / `Tilua.websocket` | Optional capabilities |

## Enable plugins

```lua
-- config
plugins = {
  "Tilua.openapi",
  "Tilua.cli",
  "Tilua.websocket",
  "MyApp.plugin.request_trace",   -- your own
}
```

Or at runtime:

```lua
app:use(require("Tilua.openapi"))
```

A plugin is a table with a `name`, an optional `priority` (lower boots first),
an optional `register(app)`, and a `hooks` table. A module whose value is a
function, or which defines `new(app)`, is called to produce that table.

## Hooks

**Hooks fire on the normal phase path.** A stock nginx configuration runs
`rewrite_by_lua` / `access_by_lua` / `content_by_lua` / `log_by_lua`; these are
the hooks those handlers emit. (`App:run()` and the HTTP channel fire the same
hooks for the non-phase entry point, and only one of the two paths runs per
request.)

```lua
app:use({
  name = "metrics",
  priority = 50,
  hooks = {
    on_boot          = function(app) end,
    on_route_loaded  = function(app, router) end,
    on_worker_init   = function(app) end,
    on_request       = function(app, ctx) end,
    on_dispatch      = function(app, ctx, matched, router) end,
    on_response      = function(app, ctx, response) end,
    on_error         = function(app, ctx, exception, matched) end,
    -- on_shutdown is declared but not emitted yet
  }
})
```

| Hook | Fires | Phase | Arguments |
|------|-------|-------|-----------|
| `on_boot` | once per master boot, after plugins are registered | `init_worker_by_lua` | `app` |
| `on_route_loaded` | once, after route rules are compiled | `init_by_lua` | `app`, `router` |
| `on_worker_init` | once per worker, after `boot_worker()` | `init_worker_by_lua` | `app` |
| `on_request` | once per request, before rewrite middleware | `rewrite_by_lua` | `app`, `ctx` |
| `on_dispatch` | once, after the route is matched and validated | `content_by_lua` | `app`, `ctx`, `matched`, `router` |
| `on_response` | once per emitted response, before it is sent | any terminal phase | `app`, `ctx`, `response` |
| `on_error` | when an error is being rendered | `content_by_lua` / error path | `app`, `ctx`, `exception`, `matched` |

### The argument contract

**`app` is always the first argument.** Several hooks run before any request
exists, and `app` is the container, so a hook can resolve whatever it needs with
`app:make("config")` / `app:make("todo_store")`. `ctx` is the request scope, or
`nil` during boot.

Details worth knowing:

- `matched` is a **rule table** (with `vals`, `midware`, `path`) when a route
  matched, `false` when routing ran and found nothing, and `nil` when routing
  never happened. Check `type(matched) == "table"` before indexing.
- `on_error` also fires for a **handler** that throws. The dispatcher catches
  handler errors so it can render a 500, and it notifies plugins before doing so.
  A middleware denial (403) is *not* an error and does not fire `on_error`.
- `on_response` fires before the body is sent, and `response.status` is
  normalised to `200` first, so a plugin never sees `0`.
- A hook that raises is caught and logged. It never breaks the request.

A complete worked example is [`examples/api/Api/plugin/request_trace.lua`](../examples/api/Api/plugin/request_trace.lua),
which records a per-request trace and exposes it at `GET /traces`.

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
bin/tilua routes      # list registered routes
bin/tilua version
bin/tilua doctor
```

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
app:use_channel({
  name = "grpc",
  priority = 40,
  match = function(app) return ngx.var.content_type == "application/grpc" end,
  handle = function(app) -- ... end,
})
```
