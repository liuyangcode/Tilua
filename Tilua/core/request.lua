--- Tilua.core.request
--- Request-scoped container context management for OpenResty.
---
--- The request context (a container whose `_parent` is the worker-level App
--- class) is parked in `ngx.ctx`.  That choice is deliberate and comes with a
--- measured caveat:
---
---   * `ngx.ctx` is per-request, survives every phase of that request, and does
---     not consume nginx variable space — verified on openresty 1.21.4.1.
---   * `ngx.ctx` is **replaced wholesale on an internal redirect** (ngx.exec,
---     error_page, try_files).  Measured: a value written in rewrite_by_lua is
---     `nil` in content_by_lua after `ngx.exec`.
---   * A subrequest gets its **own empty** `ngx.ctx`; it does not inherit the
---     parent's (measured: `is_internal() == true`, marker `nil`).
---
--- So the slot records the URI it was created for.  If the URI no longer
--- matches, the shell changed underneath us (internal redirect) and the scope
--- is rebuilt — with the previous scope released first so it cannot leak.

local M = {}

--- Key used inside `ngx.ctx`.
local SLOT = "__tilua"

--- @return table|nil the slot for the current request, if any
function M.slot()
    if not ngx or not ngx.ctx then
        return nil
    end
    return ngx.ctx[SLOT]
end

--- Is this the outermost (non-subrequest) request?
--- `is_internal()` is true for both internal redirects and subrequests, so it
--- cannot be the sole test; the slot's presence distinguishes them.
function M.is_subrequest()
    if ngx and ngx.req and ngx.req.is_internal then
        return ngx.req.is_internal() == true
    end
    return false
end

--- Current request URI, used as the slot fingerprint.
local function current_uri()
    if ngx and ngx.var then
        return ngx.var.uri or ngx.var.request_uri or "?"
    end
    return "?"
end

--- Release a scope, tolerating a missing logger.
local function release(app, ctx)
    if ctx == nil or type(ctx.flush_scope) ~= "function" then
        return 0
    end
    local ok, released, err = pcall(ctx.flush_scope, ctx)
    if not ok then
        if app and app.logger and app.logger.error then
            pcall(function()
                app.logger:error("request scope flush failed: ", tostring(released))
            end)
        end
        return 0
    end
    if err and app and app.logger and app.logger.error then
        pcall(function()
            app.logger:error("request scope flush: ", err)
        end)
    end
    return released or 0
end

M.release = release

--- Get the request context, creating it on first use in this request.
--- @param app table worker-level Application class
--- @param opts table|nil { scope = "rewrite"|"access"|"content" } for logging
function M.context(app, opts)
    local uri = current_uri()
    local slot = M.slot()

    -- Internal redirect: the shell was replaced, so the old scope is orphaned.
    -- Release it now rather than leaking it for the rest of the request.
    if slot and slot.uri ~= uri then
        release(app, slot.ctx)
        slot = nil
    end

    if slot == nil then
        local ctx = app()
        rawset(ctx, "_parent", app)
        slot = { ctx = ctx, uri = uri, flushed = false }
        if ngx and ngx.ctx then
            ngx.ctx[SLOT] = slot
        end
        if type(ctx.on_app_init) == "function" then
            ctx:on_app_init()
        end
    end

    return slot.ctx
end

--- Mark the scope as released so log_by_lua does not run it twice.
function M.mark_flushed(slot)
    if slot then
        slot.flushed = true
    end
end

--- Run the end-of-request teardown exactly once for this request.
function M.finish(app)
    local slot = M.slot()
    if not slot or slot.flushed then
        return 0
    end
    slot.flushed = true
    return release(app, slot.ctx)
end

--- Forget the slot (used when a request is abandoned early).
function M.clear()
    if ngx and ngx.ctx then
        ngx.ctx[SLOT] = nil
    end
end

return M
