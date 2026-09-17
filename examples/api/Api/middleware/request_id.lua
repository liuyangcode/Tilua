--- Content-phase middleware: tag the request with an id and add it to every
--- response.
---
--- A content-phase middleware runs before the handler and continues the chain
--- with `next_fn(...)`.  The value it returns is whatever the rest of the chain
--- produced, so post-processing is possible too.

local base = require("Tilua.middleware.base")

local tagger = (type(base.define) == "function" and base.define()) or base

function tagger:_construct(ctx, config)
    self.ctx = ctx
    self.config = config or {}
end

function tagger:handle(next_fn, ...)
    local ctx = self.ctx
    local request = ctx:make("request")

    -- The framework already generates a request id for logging/errors; reuse it
    -- so the client sees the same id that appears in the error log.
    local rid = ctx.request_id or ngx.var.request_id
    if not rid or rid == "" then
        rid = tostring(ngx.now()) .. "-" .. tostring(ngx.worker.pid())
    end
    ctx.request_id = rid

    local response = next_fn(...)

    -- `next_fn` returns the response object; decorate it before it is sent.
    if type(response) == "table" and response.set_header then
        response:set_header("X-Request-Id", rid)
    end

    return response
end

return tagger
