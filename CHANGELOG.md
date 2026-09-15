# Changelog

All notable changes to Tilua are documented in this file.

## [0.2.0] - 2026-09-15

### Added
- `Tilua.core.helpers` – pure Lua helpers (split, strip, find, deepcopy, reduce, …)
- `Tilua.core.errors` – structured TiluaError with JSON/text response helpers
- `Tilua.core.lifecycle` – OpenResty phase handlers extracted from app
- `Tilua.http.*` package: router, dispatcher, request, response
- `Tilua.middleware` as canonical middleware package
- Built-in health endpoint (`config.health_path`, default `/health`)
- Production config keys: `request_timeout`, `body_read_timeout`, `enable_json_errors`, `health_path`
- Smoke tests: helpers, errors, router, middleware
- Compatibility shims for Tilua.route / dispatch / midware, etc.

### Changed
- app.lua slimmed (~160 lines; was ~600+)
- Dispatcher uses helpers + structured error handling
- Router / request / middleware prefer helpers over hard Penlight requires
- Default dispatcher path: Tilua.http.dispatcher
- README rewritten

### Compatibility
- Existing require("Tilua.route") / Tilua.midware continue via shims
- Config accepts both middleware_* and legacy midware_* keys

## [0.1.0] - 2020

- Initial MVC kit based on OpenResty (pre-refactor)

## [0.7.0] - 2026-09-15

### Unified exceptions
- `Tilua.core.exception` – router/controller/service/database/middleware types
- API body: `{ code, message, request_id }`; production sanitizes secrets/SQL/paths
- Dispatcher + HTTP channel `xpcall`; `errors.apply` aligned
- `Service:fail`; docs/EXCEPTION.md

## [0.6.2] - 2026-09-15

### RW separation + model Query bridge
- Connection resolves master/slave endpoints from CSV host lists
- Separate keepalive pools per endpoint; SELECT prefers slave when rw_separate
- FOR UPDATE / writes still use master
- Model: to_query(), master(); Mysql selectInsert

## [0.6.1] - 2026-09-15

### Database polish
- Fixed `Query:build_select` token replacement order
- Fluent `Query.builder(db):table():where():get()/first()/count()`
- MySQL `insertAll` batch insert
- `Service:query(table)` fluent helper
- Model `_parseOptions` merge cleanup

## [0.6.0] - 2026-09-15

### Database layer restructure
```
Tilua/database/
  manager.lua      – pool by config hash
  connection.lua   – connect / keepalive
  transaction.lua  – nested-safe tx helper
  query.lua        – SQL builders + bind
  driver/mysql.lua – MySQL implementation
```
- `Tilua.db` and `Tilua.db.driver*` remain as compatibility shims

## [0.5.0] - 2026-09-15

### Service layer
- `Tilua.service.base` – business logic base (model/db/cache/transaction)
- `Tilua.service` manager – lazy load `app.service.Name`
- `App:get_service` / `Controller:service` / `Controller:model`
- docs/SERVICE.md

## [0.4.0] - 2026-09-15

### Extension architecture
- `Tilua.core.plugin` – plugin registry & hook bus
- `Tilua.core.channel` – HTTP / WebSocket / CLI entry multiplex
- Stubs: `Tilua.openapi`, `Tilua.cli`, `Tilua.websocket`
- App:use / App:channel / App:run_cli; lifecycle boots plugins from config.plugins
- docs/EXTENSIONS.md

## [0.3.0] - 2026-09-15

### Soft delete
- `soft_delete = true` or `"deleted_at"` column on model
- Auto scope on select/find; `with_trashed` / `only_trashed` / `restore` / `force_delete`

### Relations
- `hasOne` / `hasMany` / `belongsTo` / `relation(name)`
- `with(name, rows)` batch eager load
- Configure via `self.relations = { posts = { type="hasMany", model="Post", foreign_key="user_id" } }`

## [0.2.9] - 2026-09-15

### ORM query UX + hydration
- `Tilua.model.result` Row objects: get/set/to_table/save
- model: `first`, `get`, `find_by`, `value`, `pluck`, `exists`, `get_list`, `chunk`
- Optional `config.orm_hydrate = true` for automatic hydration on get_list
- Fixed stringx.strip after Penlight removal

## [0.2.8] - 2026-09-15

### ORM continued
- Process-local schema field cache (worker memory + optional Redis)
- MySQL getFields memoized per worker
- `query_bind` / `execute_bind` placeholder `?` binding via quote_sql_str
- escapeString prefers ngx.quote_sql_str
- initConnect / insert_id handling improvements
- Expanded tablex compatibility shim in model

## [0.2.7] - 2026-09-15

### ORM
- Restored model + db driver sources into tree
- Removed hard Penlight deps from model/driver/mysql (helpers)
- Field membership hash set for `_facade` filtering
- MySQL: configurable timeout/pool_size/keepalive; safer connect
- `parseKey` adds identifier backticks

## [0.2.6] - 2026-09-15

### Router performance
- Method-indexed route tables: exact map (O(1)), sorted prefixes, regex lists
- `_method_set` replaces linear method search
- `ngx.re.match(..., "jo")` instead of gmatch for single capture
- Best-match cache + candidate cache with size cap (2048)
- Prefix match anchored at path start; priority exact > regex > longest prefix
- `rebuild_index` on init / add / clear

## [0.2.5] - 2026-09-15

### Dispatcher + JSON
- Auto `response:json` for table returns when `enable_json_errors` or request wants JSON
- Status+message / status+table forms; passthrough if handler returns response object
- Structured errors respect JSON preference

### CSRF
- Auto-check unsafe methods; session + double-submit cookie (SameSite configurable)
- Accepts body field / header / cookie; rotates token after success
- View helpers `__CSRF__` and `__CSRF_META__`

### util.lua
- Soft-load Penlight; split/bind1/empty/is_array via helpers
- dump/extend work without Penlight

## [0.2.4] - 2026-09-15

### Request / Response
- Response: `json` / `text` / `html` / `no_content`, `attachment` / `inline`, chainable API
- Response: fix send_body for non-200 with body; sync ngx.status via set_status
- Response: table body auto-JSON; Content-Length maintained
- Request: `is_get/post/put/delete`, `is_ajax`, `is_json`, `wants_json`
- Request: `input(key)`, `client_ip` (trust_proxy), `bearer_token`
- Request: cookie jar + cached headers; lazy user-agent; safer get_pid
- tests/test_request_response_api.lua

## [0.2.3] - 2026-09-15

### Cookie module
- New `Tilua.http.cookie`: build / parse / encode / clear
- Response: `set_cookie` supports raw string, opts table, positional args; `clear_cookie`
- Request: parse `Cookie` header once into jar + ngx.var fallback
- Session uses cookie builder (Max-Age, SameSite, Secure, Path, Domain)
- SameSite=None automatically adds Secure
- tests/test_cookie.lua

## [0.2.2] - 2026-09-15

### Session rewrite
- Consistent colon-style API; fixed decode/destroy self bugs
- `_dirty` flag + lazy_write skips unchanged payloads
- Safer probabilistic GC (no per-request randomseed)
- Session id validation (length/charset)
- Cookie: HttpOnly, optional Secure, SameSite=Lax, Max-Age
- Middleware caches save_handler module; only sets cookie when present
- Redis handler restored + `Tilua.session.redis` alias
- New `Tilua.session.memory` handler for tests/dev
- pcall around start/write so session errors do not crash requests
- tests/test_session.lua

## [0.2.1] - 2026-09-15

### Fixed
- `App:run` now uses `route.run` (correct best-match + validation) instead of raw `find_matched_route` list

### Performance
- Router no longer deep-copies full rule caches on every request; shallow-copies only rules that need mutation
- Matched-rule cache returns by reference

### Changed
- cache / db / model / session / mvc_router / body_parser / html_cache / lifecycle prefer `Tilua.core.helpers`
- Soft-optional Penlight only for `makepath` when available
