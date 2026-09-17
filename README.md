# Tilua

**A simple, modern MVC web development kit for OpenResty (Lua).**

> Status: **v0.9.3** — container-based architecture, trie router, phase-split
> middleware, request-scoped lifecycle. See `docs/` for the design notes and
> `VERSION` for the current release. Originally marked "Production not ready".  
> Goal: cleaner architecture, better maintainability, production-ready defaults while keeping the original spirit.


## Features

- Classic **MVC** + flexible **route-based** style
- Deep integration with OpenResty lifecycle (`init_by_lua`, `init_worker_by_lua`, etc.)
- Middleware pipeline (session, body parser, JSON, CSRF, HTML cache…)
- Built-in support for MySQL / Redis / shared dict cache
- Built-in template engine (`Tilua.template`) — no external rendering dependency
- Lightweight custom class system + utilities

## Requirements

- OpenResty ≥ 1.15 (recommended latest)
- LuaJIT (bundled with OpenResty)
- Optional: Redis, MySQL

### Dependencies

| Library | Purpose |
|---------|---------|
| [lua-resty-redis](https://github.com/openresty/lua-resty-redis) | Cache / Session |
| [lua-resty-mysql](https://github.com/openresty/lua-resty-mysql) | Database |
| LuaFileSystem (`lfs`, bundled with OpenResty) | Required by `Tilua.utils.path` |
| [lua-resty-jit-uuid](https://github.com/thibaultcha/lua-resty-jit-uuid) | UUID generation |

**No Penlight dependency.** Earlier versions soft-loaded `pl.tablex` / `pl.pretty`
and speculative `pl.dir`, with hand-rolled fallbacks. Penlight is not installed in
a stock OpenResty, so those branches were dead code; the pure-Lua replacements now
live in `Tilua.core.helpers` (`update` / `size` / `foreach` / `pretty`).

## Quick Start

### Fastest path

```bash
tilua doctor   # verify OpenResty, required modules and writable dirs
tilua serve    # generate a dev nginx.conf and boot OpenResty on :8001
```

`tilua serve` autodetects your app module (a `<Name>/app.lua` in the project
root), writes `.tilua/dev.nginx.conf`, and runs OpenResty in the foreground.
`lua_code_cache` is off, so edited Lua is picked up on the next request — only
nginx.conf changes need a restart.

```
tilua serve --port 8080      # different port
tilua serve --app MyApp      # skip autodetection
tilua serve --print-conf     # just show the config, start nothing
```

The generated config is development-only. For production, write your own
nginx.conf — `--print-conf` output is a reasonable starting point.

### 1. Scaffold

```bash
tilua new MyApp && cd MyApp
tilua serve
```

That generates the layout below. The rest of this section explains what the
generated files do, if you would rather write them yourself.

### 2. Nginx configuration

```nginx
lua_package_path "$prefix/lua/?.lua;$prefix/lualib/?.lua;;";
lua_shared_dict app_cache 10m;

server {
    listen 8001;

    location ~* \.(css|js|jpg|jpeg|png|gif|ico)$ {
        root /var/web;
        expires 7d;
    }

    location / {
        # development only
        lua_code_cache off;

        content_by_lua_block {
            require("MyApp.app")():run()
        }
    }
}
```

### 3. Application entry (`MyApp/app.lua`)

```lua
local App = require("Tilua.app").define()

-- Class fields, not instance fields: the base constructor reads these while
-- building the instance, so setting them in _construct would be too late.
App.name   = "MyApp"   -- must match the require path
App.status = "dev"     -- loads config/dev.lua if present
App.debug  = true

-- Optional: register application-owned services.
function App:_construct(opts)
    return self
end

return App
```

### 4. Routes (`MyApp/routes.lua`) – two styles

**Style A – Closure / Express-like**

```lua
local route    = require("Tilua.http.router")
local response = require("Tilua.http.response")

route.get("/", function()
    return response("Hello Tilua!")
end)

route.get("/user/welcome/{name}", function(ctx, name)
    return response("Welcome " .. name .. "!")
end)
```

(`Tilua.route` and `Tilua.response` still work as compatibility shims.)

**Style B – Classic MVC Controller**

```lua
-- MyApp/controller/index.lua
local Index = require("Tilua.controller").define()

function Index:index(request, name)
    return "welcome, " .. (name or "guest")
end

return Index
```

Controllers resolve as `<App>/controller/<controller>.lua`; the second path
segment selects the action and defaults to `index`.

## Project Structure (after refactor)

```
Tilua/
├── app.lua                 # Application core (slim)
├── core/                   # Class, config loader, logger helpers
├── http/                   # request / response / router / dispatcher
├── middleware/             # body_parser, session, csrf, json...
├── db/  cache/  session/   # Data layer
├── model/  view/           # MVC pieces
├── utils/                  # path, util, class, useragent...
└── config/default.lua
```

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/ROUTER.md](docs/ROUTER.md) | Router guide: trie matching, parameters, wildcards, validation, middleware phases |
| [docs/CONTAINER.md](docs/CONTAINER.md) | Application IoC container: service bindings and scopes |
| [docs/LIFECYCLE.md](docs/LIFECYCLE.md) | OpenResty lifecycle: phases, request scope, measured semantics |
| [docs/SERVICE.md](docs/SERVICE.md) | Service layer |
| [docs/EXCEPTION.md](docs/EXCEPTION.md) | Unified exceptions |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md) | Plugins / channels |
| [docs/ANALYSIS.md](docs/ANALYSIS.md) | Full technical review of the codebase |


## Configuration

Configuration is layered:

1. `Tilua.config.default`
2. `YourApp.config.default`
3. `YourApp.config.{status}`  (e.g. `dev`, `prod`)

See `Tilua/config/default.lua` for all available options.

## Development Roadmap

- [x] Phase 1 – Directory restructuring & core split
- [x] Phase 2 – Package restructure (http/, middleware/) + shims
- [x] Phase 3 – Helpers, structured errors, health endpoint, tests, CHANGELOG/VERSION
- [ ] Phase 4 – Documentation site & more examples

## License

MIT License  
Copyright (c) 2020–2026 liuyangcode

## Contributing

This is currently a personal project under active refactoring.  
Issues and PRs are welcome once the core structure stabilizes.
