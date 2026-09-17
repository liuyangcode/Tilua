# Tilua

**A simple, modern MVC web development kit for OpenResty (Lua).**

> Status: **v0.9.3** — container-based architecture, trie router, phase-split
> middleware, request-scoped lifecycle. See [`docs/`](docs/) for the design
> notes and [`VERSION`](VERSION) for the current release.

---

## Try it in 60 seconds

No OpenResty, no LuaRocks, no database — just Docker:

```bash
git clone https://github.com/liuyangcode/Tilua && cd Tilua/examples/hello
docker compose up --build
# open http://localhost:8080
```

That is a real Tilua application: a template-rendered page, a path parameter, a
JSON endpoint, and a structured 500 — in about 60 lines of app code.

Want more? [`examples/api`](examples/api/) adds container services,
phase-split middleware, parameter validation and an auth guard:

```bash
cd ../api && docker compose up --build
# open http://localhost:8081
```

Already have OpenResty? See [Run the examples](examples/README.md).

---

## What it gives you

- **Classic MVC *and* a route-based style** — use whichever fits, in the same app
- **Trie router** — O(path segments) matching, `{name}` parameters, wildcards,
  and declarative per-parameter validation
- **IoC container** — `singleton` / `scoped` / `bind` / `alias` / `extend`, with
  request-scoped services released automatically at end of request
- **Middleware split by OpenResty phase** — `rewrite` / `access` / `content`,
  declared globally or per route
- **Built-in template engine** — no external rendering dependency
- **Structured errors** — one JSON error shape with a request id, and no stack
  traces or filesystem paths leaked in production

## Requirements

- **OpenResty ≥ 1.15** (bundles LuaJIT). Stock nginx will not work — it has no
  `ngx_lua` module.
- That is the whole list. There are **no LuaRocks dependencies**.

| Optional | Why you might want it |
|----------|-----------------------|
| [lua-resty-redis](https://github.com/openresty/lua-resty-redis) | Redis-backed cache / session |
| [lua-resty-mysql](https://github.com/openresty/lua-resty-mysql) | MySQL database |
| LuaFileSystem | `path.dir` and symlink queries (everything else has a pure-Lua fallback) |

> Earlier versions required Penlight, LuaFileSystem and lua-resty-jit-uuid at
> load time. Penlight is gone entirely, and `lfs` / `jit-uuid` are optional with
> pure-Lua fallbacks — a stock `openresty/openresty` image runs the framework
> as-is. See [`CHANGELOG.md`](CHANGELOG.md).

---

## Quick start (with OpenResty installed)

```bash
git clone https://github.com/liuyangcode/Tilua && cd Tilua

./bin/tilua doctor             # check the environment
./bin/tilua new MyApp          # scaffold a runnable project
cd MyApp && ../bin/tilua serve # http://localhost:8001
```

`bin/tilua` finds the framework from its own location, so the commands above
work from anywhere inside the checkout. To use it from outside (or as a
standalone command), point `TILUA_ROOT` at the directory containing `Tilua/`:

```bash
export TILUA_ROOT=/path/to/Tilua
alias tilua="$TILUA_ROOT/bin/tilua"

cd ~/projects && tilua new MyApp && cd MyApp && tilua serve
```

`tilua serve` writes `.tilua/dev.nginx.conf` with `lua_code_cache off`, so edits
to your Lua are picked up on the next request — only `nginx.conf` changes need a
restart.

| Flag | Meaning |
|------|---------|
| `--port N` | listen port (default 8001) |
| `--app Name` | skip app autodetection |
| `--root DIR` | project root (default: current directory) |
| `--print-conf` | print the generated config and exit |

> The generated config is **development only**. For production write your own —
> `--print-conf` is a reasonable starting point.

---

## The pieces

### Application entry (`MyApp/app.lua`)

```lua
local App = require("Tilua.app").define()

-- Class fields: the base constructor reads these while building the instance,
-- so setting them inside _construct would be too late.
App.name   = "MyApp"   -- must match the directory / require path
App.status = "dev"     -- loads config/dev.lua on top of config/default.lua
App.debug  = true      -- verbose errors; set false in production

-- Register your own services. The framework already binds config, logger,
-- router, request, response, view, cache, model and service.
function App:_construct(opts)
    self:singleton("clock", function(c)
        return { now = ngx.now }
    end)

    -- One instance per request, released automatically at end of request.
    self:scoped("request_log", function(c)
        local entries = {}
        return {
            add = function(what) entries[#entries + 1] = what end,
            close = function() c.logger:debug("released") end,
        }
    end)

    return self
end

return App
```

### Routes (`MyApp/routes.lua`)

```lua
local route = require("Tilua.http.router")
local errors = require("Tilua.core.errors")

-- Return a table  -> JSON
route.get("/api/ping", function()
    return { pong = true }
end)

-- Return (view_name, context) -> render view/index.html
route.get("/", function(ctx)
    return "index", { title = ctx:make("config").app_title }
end)

-- A path parameter arrives as a positional argument
route.get("/user/{name}", function(ctx, name)
    return "Hello, " .. name
end)

-- Declarative validation. A request that fails it is a 404, never a crash.
route["get /num/{id} id:reg,^[0-9]+$"] = function(ctx, id)
    return { id = tonumber(id) }
end

route["get /echo/{mode} mode:in,upper,lower"] = function(ctx, mode)
    return { mode = mode }
end

-- A route-scoped access-phase guard: gates only this route.
route.get("/admin", function()
    return { ok = true }
end, nil, { phases = { access = { "admin_guard" } } })

route.get("/missing", function()
    return errors.not_found("no such thing")
end)
```

Handler return values are normalised for you:

| You return | Client gets |
|------------|-------------|
| a Lua table | JSON |
| a string | `text/plain` |
| `a response` object | sent as-is (status, headers, cookies) |
| `(view_name, table)` | `view/<view_name>.html` rendered |
| a number | that HTTP status |
| `errors.*` | structured JSON error with the right status |

### Middleware

Middleware is bound to an OpenResty **phase**, globally or per route:

```lua
-- config/dev.lua
return {
    middleware_phases = {
        rewrite = { "html_cache" },                        -- early short-circuit
        access  = { "auth", "rate_limit" },                -- may deny the request
        content = { "body_parser", "session", "mvc" },     -- default home
    },
}
```

A middleware's `handle(next_fn, ...)` either continues the chain with
`next_fn(...)` or returns a response to short-circuit. See
[`examples/api/Api/middleware/`](examples/api/Api/middleware/) for two annotated
examples.

### Convention-based routes (`auto_routes`)

For MVC apps, set `auto_routes = true` and skip `routes.lua` entirely: worker
boot scans `<App>/controller/` and registers a route per public action.

```lua
-- MyApp/controller/user.lua
--- @get  /users/{id}
--- @post /users
--- @middleware auth
--- @phases access = rate_limit
function User:update(id) ... end

function User:index() ... end     -- no annotation -> GET /user/index
```

| Directive | Meaning |
|-----------|---------|
| `@get` `@post` `@put` `@delete` `@patch` `@head` `@options` | One route per directive. The path is optional and defaults to `/<controller>/<action>`; repeat the directive to serve several methods. |
| `@route <methods> [path]` | The long form, kept for compatibility. Accepts a method list: `@route get,post /thing`. |
| `@middleware <entry>` | Content-phase middleware; repeatable, accepts `name`, `name, { config }`, `[group]` |
| `@phases <phase> = <entry>` | Middleware for a non-content phase (`access` / `rewrite`) |

Directive names are lowercase and case-sensitive, so a stray `@GET` is reported
rather than silently ignored.

An unannotated action keeps the convention default, so adding annotations never
changes the routes you did not touch. Private actions (leading `_`) and the
framework's controller base methods are never registered. An explicit
`routes.lua` (or `config.route`) entry always wins over a discovered route for
the same method and path.

See [`examples/api/Api/controller/demo.lua`](examples/api/Api/controller/demo.lua)
for a working example.

### Nginx configuration

`init_by_lua` / `init_worker_by_lua` are http-level; the four request phases
live inside `location /`:

```nginx
http {
    # The prefix (set with -p) must contain Tilua/. Paths are relative to it.
    lua_package_path "./?.lua;./?/init.lua;;";
    lua_shared_dict app_cache 10m;      # must match config.SHDICIT_NAME

    init_by_lua_block       { require("MyApp.app"):init_by_lua() }
    init_worker_by_lua_block { require("MyApp.app"):init_worker_by_lua() }

    server {
        listen 8001;

        location ~* \.(css|js|png|jpg|svg|woff2?)$ {
            root public;
        }

        location / {
            rewrite_by_lua_block { require("MyApp.app"):rewrite_by_lua() }
            access_by_lua_block  { require("MyApp.app"):access_by_lua()  }
            content_by_lua_block { require("MyApp.app"):content_by_lua() }
            log_by_lua_block     { require("MyApp.app"):log_by_lua()     }
        }
    }
}
```

Every block is required: `rewrite` creates the request scope, `content` is the
only phase that writes a body, and `log` releases scoped services.

> **There is no `$prefix` variable in OpenResty's nginx.** Use paths relative to
> the `-p` prefix, as above.

### Configuration

Layered, later wins:

1. `Tilua/config/default.lua`
2. `MyApp/config/default.lua`
3. `MyApp/config/<status>.lua` — selected by `App.status`

See [`Tilua/config/default.lua`](Tilua/config/default.lua) for every option.

---

## Project layout

```
Tilua/
├── app.lua              Application = IoC container
├── core/                container, request scope, lifecycle, errors, plugins
├── http/                request, response, router (trie), dispatcher
├── middleware/          body_parser, session, csrf, json, html_cache, mvc…
├── template/            built-in template engine
├── utils/               path, util, class, strings, tables…
├── cli/                 routes / version / doctor / serve / new
├── cache/ db/ model/    data layer
└── config/default.lua
bin/tilua                CLI entry point
examples/                two runnable applications
tests/                   unit suites, e2e under real nginx, example smoke tests
docs/                    design notes
```

---

## Documentation

| Doc | Contents |
|-----|----------|
| [examples/README.md](examples/README.md) | How to run and read the two example apps |
| [docs/ROUTER.md](docs/ROUTER.md) | Trie matching, parameters, wildcards, validation, phases |
| [docs/CONTAINER.md](docs/CONTAINER.md) | Service bindings and scopes |
| [docs/LIFECYCLE.md](docs/LIFECYCLE.md) | Phase model and measured OpenResty semantics |
| [docs/SERVICE.md](docs/SERVICE.md) | Service layer |
| [docs/EXCEPTION.md](docs/EXCEPTION.md) | Unified exceptions |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md) | Plugins and channels |
| [docs/ANALYSIS-2.md](docs/ANALYSIS-2.md) | Technical review with verified findings |

## Development

```bash
# unit suites
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
    luajit tests/support/lua_stub.lua tests/test_trie_router.lua

# end-to-end under real nginx (19 cases)
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
    sh tests/e2e/run.sh

# both examples
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
    sh tests/run_examples.sh

# parse-check every Lua file
docker run --rm -v "$PWD:/app" -w /app openresty/openresty:1.21.4.1-buster \
    sh tests/syntax_check.sh
```

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| Every route 404s | Your `app.lua` / `routes.lua` failed to load. `nginx -t` validates only the *config*; check `logs/error.log`. |
| `unknown "prefix" variable` | You used `$prefix`. Use relative paths plus `-p`. |
| `unknown directive "content_by_lua_block"` | Stock nginx, not OpenResty. |
| `module 'Tilua.app' not found` | `lua_package_path` does not cover the prefix, or `-p` points elsewhere. |
| `App.name must be set before the config can be loaded` | Assign `App.name` before anything calls `init_by_lua`. |
| `lua entry thread aborted: runtime error` | An error outside the dispatcher's protection — usually in a phase middleware or the router. Check `logs/error.log`. |

## Roadmap

- [x] Phase 1 – Directory restructuring & core split
- [x] Phase 2 – Package restructure (`http/`, `middleware/`) + shims
- [x] Phase 3 – Helpers, structured errors, health endpoint, tests
- [x] Phase 4 – Dependency removal (Penlight), IoC container, trie router
- [ ] Phase 5 – Documentation site

## License

MIT License
Copyright (c) 2020–2026 liuyangcode

## Contributing

This is a personal project under active refactoring. Issues and PRs are welcome
once the core structure stabilizes.
