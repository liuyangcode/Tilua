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
