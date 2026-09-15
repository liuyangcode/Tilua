# Tilua Refactor Notes

## Phase 1 – Core split (done)

- `app.lua` reduced from ~609 lines → ~160 lines
- Lifecycle handlers extracted to `Tilua.core.lifecycle`
- New professional README

## Phase 2 – Package restructure (done)

### Directory changes

```
Tilua/
├── app.lua
├── core/
│   └── lifecycle.lua
├── http/                          ← NEW
│   ├── router.lua                 (was route.lua)
│   ├── dispatcher.lua             (was dispatch.lua)
│   ├── request.lua
│   └── response.lua
├── middleware/                    ← NEW canonical name
│   ├── init.lua                   (manager)
│   ├── base.lua
│   ├── body_parser.lua
│   ├── session.lua
│   └── …
├── midware.lua                    ← compatibility shim → middleware
├── route.lua / dispatch.lua       ← compatibility shims → http.*
├── request.lua / response.lua     ← compatibility shims
└── …
```

### Compatibility strategy

| Old require                        | New preferred require              | Status   |
|------------------------------------|------------------------------------|----------|
| `Tilua.route`                      | `Tilua.http.router`                | shim OK  |
| `Tilua.dispatch`                   | `Tilua.http.dispatcher`            | shim OK  |
| `Tilua.request` / `Tilua.response` | `Tilua.http.request` / `.response` | shim OK  |
| `Tilua.midware`                    | `Tilua.middleware`                 | shim OK  |

Config keys:
- Prefer `middleware_alias` / `middleware_group`
- Legacy `midware_alias` / `midware_group` still accepted

Default dispatcher path is now `Tilua.http.dispatcher` (old value still works via shim).

### Other Phase-2 improvements

- Middleware manager rewritten under the new name with cleaner error messages
- Config supports both old and new key names
- Basic router smoke test added under `tests/`

## Phase 3 – Planned

- Further reduce Penlight usage on hot paths
- Structured error handling & logging helpers
- More unit tests (middleware chain, response rendering)
- Production defaults (timeouts, health endpoint example)
- Changelog & semantic versioning

## Migration tips for application code

1. No immediate change required – shims keep everything working.
2. When convenient, update your own `require`s and config keys to the new names.
3. Point `lua_package_path` at the new tree (or replace the old `Tilua/` folder after backup).
