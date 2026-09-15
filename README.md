# Tilua

**A simple, modern MVC web development kit for OpenResty (Lua).**

> Status: **v0.2.0** (Phase 1–3 complete). Originally marked "Production not ready".  
> Goal: cleaner architecture, better maintainability, production-ready defaults while keeping the original spirit.


## Features

- Classic **MVC** + flexible **route-based** style
- Deep integration with OpenResty lifecycle (`init_by_lua`, `init_worker_by_lua`, etc.)
- Middleware pipeline (session, body parser, JSON, CSRF, HTML cache…)
- Built-in support for MySQL / Redis / shared dict cache
- Template rendering via `lua-resty-template`
- Lightweight custom class system + utilities

## Requirements

- OpenResty ≥ 1.15 (recommended latest)
- LuaJIT (bundled with OpenResty)
- Optional: Redis, MySQL

### Dependencies

| Library | Purpose |
|---------|---------|
| [lua-resty-template](https://github.com/bungle/lua-resty-template) | Views |
| [lua-resty-redis](https://github.com/openresty/lua-resty-redis) | Cache / Session |
| [lua-resty-mysql](https://github.com/openresty/lua-resty-mysql) | Database |
| Penlight (vendored or system) | Utilities (being reduced) |

## Quick Start

### 1. Nginx configuration

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

### 2. Application entry (`MyApp/app.lua`)

```lua
local App = require("Tilua.app").derive()

function App:_init()
    self.name      = "MyApp"          -- must match the require path
    self.module    = "Home"           -- default controller module
    self.debug     = true
    self.status    = "dev"            -- loads config/dev.lua if exists
    self:super(self)
end

return App
```

### 3. Routes (`MyApp/routes.lua`) – two styles

**Style A – Closure / Express-like**

```lua
local route    = require("Tilua.route")
local response = require("Tilua.response")

route.get("/", function()
    return response("Hello Tilua!")
end)

route.get("/user/welcome/{name}", function(ctx, name)
    return response("Welcome " .. name .. "!")
end)
```

**Style B – Classic MVC Controller**

```lua
-- MyApp/Home/controller/index.lua
local Index = require("Tilua.controller").derive()

function Index:index(request, name)
    return "welcome, " .. (name or "guest")
end

return Index
```

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
