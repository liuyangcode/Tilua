# Unified Exceptions

Module: `Tilua.core.exception`

## API response (production-safe)

```json
{
  "code": 500,
  "message": "Internal Server Error",
  "request_id": "abc-..."
}
```

- **Production** (`debug=false` / `env=production`): no stack, no SQL, no paths, no secrets.
- **Development**: sanitized message + optional `error_code` / `layer` / `details`.
- Header: `X-Request-Id`

## Layers

| Constructor | Default status | Code |
|-------------|----------------|------|
| `Exception.router` | 404 | router_error |
| `Exception.controller` | 500 | controller_error |
| `Exception.service` | 422 | service_error |
| `Exception.database` | 500 | database_error |
| `Exception.middleware` | 500 | middleware_error |
| `Exception.http` | 500 | http_error |

Also: `Tilua.core.errors` helpers (`not_found`, `bad_request`, …) map into the same pipeline.

## Usage

```lua
-- Controller
self:fail("invalid input", 400)

-- Service
self:fail("email taken", 409)
self:fail_not_found("user")

-- Manual
local Exception = require("Tilua.core.exception")
error(Exception.database("connect failed"), 0)

-- Return structured error (no throw)
return require("Tilua.core.errors").not_found()
```

## Pipeline

```
Channel (router xpcall)
  → Dispatcher (controller + middleware xpcall)
    → Exception.log (server only)
    → Exception.render → JSON body
```
