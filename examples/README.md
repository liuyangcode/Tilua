# Examples

Two runnable applications. Both start with **one command** and need no database,
no Redis, and no LuaRocks packages.

| Example | What it shows | Port |
|---------|---------------|------|
| [`hello`](hello/) | The whole request flow in four routes: a view, a path parameter, a JSON table, a handler that throws | 8080 |
| [`api`](api/) | Everything past "hello world": container services, phase-split middleware, parameter validation, structured errors, JSON bodies, scoped state | 8081 |

---

## Run them

### Option A — Docker (nothing to install)

```bash
cd examples/hello
docker compose up --build
# -> http://localhost:8080
```

```bash
cd examples/api
docker compose up --build
# -> http://localhost:8081
```

Ctrl-C stops it. The build context is the repository root, so the image contains
both the framework and the example.

### Option B — OpenResty installed locally

`nginx` must be OpenResty (stock nginx has no `ngx_lua`). From the **repository
root**:

```bash
mkdir -p logs examples/hello/logs
openresty -p "$PWD" -c examples/hello/nginx.conf
# -> http://localhost:8080
```

- `-p "$PWD"` is the *prefix*: every relative path in the example's
  `nginx.conf` resolves against it. It must be the repository root because that
  is where `Tilua/` lives.
- OpenResty's nginx has **no `$prefix` variable** — relative paths are how you
  write a prefix-independent config.

### Option C — `tilua serve` (development, config generated for you)

From the repository root:

```bash
./bin/tilua serve --root . --port 8080
```

Or from the example's own directory, since the CLI locates the framework by
its own path:

```bash
cd examples/hello
../../bin/tilua serve
```

This writes `.tilua/dev.nginx.conf` with `lua_code_cache off`, so edited Lua is
picked up on the next request and only `nginx.conf` changes need a restart.

### Check an example without starting a server

```bash
sh tests/run_example.sh examples/hello 8080
sh tests/run_example.sh examples/api   8081
```

Each example ships a `.expect` file listing path → expected status. The runner
boots nginx, requests every path, prints `status + body`, and exits non-zero if
any expectation fails.

---

## `hello` — the request flow

Four routes, each demonstrating one idea:

| Route | Demonstrates |
|-------|--------------|
| `GET /` | `return "index", { context }` renders `Hello/view/index.html` |
| `GET /hello/{name}` | A captured path parameter arrives as a positional argument |
| `GET /api/ping` | Returning a Lua table produces JSON automatically |
| `GET /boom` | A thrown error becomes a structured JSON 500 with a request id |

Plus `GET /from-config`, which is declared in `Hello/config/dev.lua` rather than
in `routes.lua`, to show that rules can come from config too.

Files worth reading, in order:

1. `Hello/routes.lua` — the routes
2. `Hello/app.lua` — `name` / `status` / `debug`, and a custom service
3. `Hello/config/dev.lua` — configuration layering
4. `Hello/view/index.html` — the template
5. `nginx.conf` — the phase wiring

---

## `api` — a realistic service

An in-memory todo API. No external services.

| Route | Demonstrates |
|-------|--------------|
| `GET /` | An index response |
| `GET /health` | A liveness endpoint |
| `GET /todos` | Reading from a worker-scoped container service |
| `POST /todos` | Parsing a JSON body; a structured `bad_request` on missing input |
| `GET /todos/{id}` | `id:reg,^[0-9]+$` validation — a bad id is a 404, not a 500 |
| `DELETE /todos/{id}` | The same validation, different method |
| `GET /echo/{mode}` | `mode:in,upper,lower` — validating against a value list |
| `GET /admin/stats` | A route-scoped **access-phase** guard (`X-Api-Token`) |
| `GET /traces` | Plugin hooks on the phase path |
| `GET /demo/*` | **Auto-discovered** from `Api/controller/demo.lua` — no `routes.lua` entry |

The last one is convention-based routing: `auto_routes = true` (in
`Api/config/dev.lua`) makes worker boot scan `Api/controller/` and register a
route per public action. `demo.lua`'s `Demo:hello` becomes `GET /demo/hello`
without being declared anywhere.

An action can declare its own method and middleware with annotations:

```lua
--- @get  /demo/echo/{word}
--- @post /demo/echo
--- @middleware request_id
--- @phases access = api_token
function Demo:echo(word) ... end
```

| Directive | Meaning |
|-----------|---------|
| `@get` `@post` `@put` `@delete` `@patch` `@head` `@options` | One route per directive; the path is optional and defaults to `/<controller>/<action>` |
| `@route <methods> [path]` | Long form, kept for compatibility (`@route get,post /thing`) |
| `@middleware <entry>` | Content-phase middleware (repeatable) |
| `@phases <phase> = <entry>` | Middleware for `access` / `rewrite` |

```bash
curl http://localhost:8081/demo/hello      # unannotated -> GET /demo/hello
curl http://localhost:8081/demo/echo/hi    # @route GET /demo/echo/{word}
curl -X POST http://localhost:8081/demo/echo
curl -i http://localhost:8081/demo/secure  # @phases access = api_token -> 401
curl -i http://localhost:8081/demo/_secret # 404 - leading _ is private
```

Things worth knowing: an **unannotated** action keeps the convention default, so
annotating one action never changes another; and an explicit `routes.lua` entry
always wins over a discovered route for the same method and path.

### Exposing only annotated actions

`auto_routes_unannotated` controls whether an action with no route annotation is
still registered:

```lua
auto_routes = true,
auto_routes_unannotated = false,   -- true by default
```

| Value | `Demo:hello` (no annotation) | `Demo:echo` (`@get` / `@post`) |
|-------|------------------------------|-------------------------------|
| `true` (default) | exposed as `GET /demo/hello` | exposed |
| `false` | **404**, and listed in the discovery report | exposed |

It defaults to `true` so enabling it cannot silently un-route a project that
relies on convention routes. Use `false` when the controller should be the
complete, explicit list of endpoints — the skipped actions appear in
`app._discovery_report.skipped`, so the omission is visible.

```bash
# the index lists every endpoint
curl http://localhost:8081/

# validation: 404 rather than a crash
curl -i http://localhost:8081/todos/abc

# the access guard only gates /admin/stats
curl -i http://localhost:8081/admin/stats                       # 401
curl -i -H 'X-Api-Token: wrong' http://localhost:8081/admin/stats   # 403
curl -i -H 'X-Api-Token: secret' http://localhost:8081/admin/stats  # 200
```

Files worth reading:

1. `Api/routes.lua` — routes, validation specs, per-route phase middleware
2. `Api/app.lua` — singleton vs **scoped** services and why the difference matters
3. `Api/middleware/api_token.lua` — an access-phase guard
4. `Api/middleware/request_id.lua` — a content-phase decorator
5. `Api/config/dev.lua` — binding middleware to phases
6. `Api/config/prod.lua` — production overrides

---

## Writing your own

```bash
./bin/tilua new MyApp
cd MyApp
./bin/tilua serve
```

That scaffolds the same layout the examples use. Then see
[`docs/ROUTER.md`](../docs/ROUTER.md) for the routing DSL,
[`docs/CONTAINER.md`](../docs/CONTAINER.md) for services, and
[`docs/LIFECYCLE.md`](../docs/LIFECYCLE.md) for the phase model.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| Every route 404s | The app module failed to load. Check `logs/error.log` — a Lua error in `app.lua` / `routes.lua` at boot leaves the router with zero rules. `nginx -t` only checks the *config*, not your Lua. |
| `unknown "prefix" variable` | You used `$prefix`. OpenResty's nginx has no such variable; use relative paths plus `-p`. |
| `unknown directive "content_by_lua_block"` | You are running stock nginx, not OpenResty. |
| `module 'Tilua.app' not found` | `lua_package_path` does not cover the repository root, or `-p` points somewhere else. |
| `init_by_lua error: ... App.name must be set` | `App.name` is assigned after `Tilua.app.define()` but before anything calls `init_by_lua`. |
