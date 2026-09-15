--- Guard middleware: deny unless the admin token header matches.
--- Uses the request object's `get_header`, which reads headers live (a snapshot
--- taken during rewrite can miss custom headers).
local base = require("Tilua.middleware.base")
local errors = require("Tilua.core.errors")

local guard = (type(base.define) == "function" and base.define()) or base

--- Middleware are instantiated as `class(ctx, config)`; without this the guard
--- would have no `self.config` and no `self.ctx`.
function guard:_construct(ctx, config)
    self.ctx = ctx
    self.config = config or {}
end

function guard:handle(next_fn, ...)
    local ctx = self.ctx
    -- Read headers live: the request object's snapshot is taken during rewrite,
    -- where OpenResty may not yet expose custom headers.
    local headers = ngx.req.get_headers()
    local token = headers["x-admin-token"] or headers["X-Admin-Token"]
    local expected = self.config.token or "letmein"

    if token ~= expected then
        -- Deny: return a structured error; the access phase emits it and stops,
        -- so the content phase never runs for this request.
        return errors.forbidden("admin token required", "admin_denied")
    end

    return next_fn(...)
end

return guard
