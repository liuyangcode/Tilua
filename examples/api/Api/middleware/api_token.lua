--- Access-phase middleware: require a shared token header.
---
--- Location in the pipeline is declared by whoever uses it:
---   * globally  -> config.middleware_phases.access
---   * per route -> route.get(path, handler, nil, { phases = { access = {...} } })
---
--- Returning anything non-nil from a phase middleware short-circuits the
--- request; the phase emits it and the content phase never runs.

local base = require("Tilua.middleware.base")
local errors = require("Tilua.core.errors")

local guard = (type(base.define) == "function" and base.define()) or base

--- Middleware are constructed as `class(ctx, config)`, so `self.ctx` and
--- `self.config` must be stored here.
function guard:_construct(ctx, config)
    self.ctx = ctx
    self.config = config or {}
end

function guard:handle(next_fn, ...)
    -- Read headers live.  `ngx.req.get_headers()` during rewrite can miss
    -- custom headers, which is why the request object reads them on access
    -- rather than from a snapshot.
    local headers = ngx.req.get_headers()
    local token = headers["x-api-token"] or headers["X-Api-Token"]

    if not token or token == "" then
        return errors.unauthorized("X-Api-Token header required", "missing_token")
    end

    local expected = self.config.token
        or (self.ctx.config and self.ctx.config.api_token)
        or "secret"

    if token ~= expected then
        return errors.forbidden("invalid API token", "bad_token")
    end

    --- Record on the request-scoped service, proving scoped state works.
    local log = self.ctx:make("request_log")
    if log then
        log:add("admin request authorised")
    end

    -- Admission granted: continue the chain.
    return next_fn(...)
end

return guard
