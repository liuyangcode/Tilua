--- Request tracing plugin for the Api example.
---
--- Demonstrates the framework's plugin hooks on the PHASE path.  Enable it in
--- config/dev.lua:
---
---     plugins = { "Api.plugin.request_trace" }
---
--- Hook contract (see docs/EXTENSIONS.md):
---
---     on_boot         (app)
---     on_route_loaded (app, router)
---     on_worker_init  (app)
---     on_request      (app, ctx)
---     on_dispatch     (app, ctx, matched, router)
---     on_response     (app, ctx, response)
---     on_error        (app, ctx, exception, matched)
---     on_shutdown     (app)
---
--- `app` is always the first argument and is the container, so a hook can
--- resolve services with `app:make(...)`.  `ctx` is the request scope, or nil in
--- the boot hooks.  A hook that throws is caught and logged, never breaking the
--- request.

local Trace = {
    name = "request_trace",
    priority = 60,          -- lower runs first; boot hooks fire in this order

    -- Bounded ring buffer of the last N requests, readable from /traces.
    _log = {},
    _limit = 20,
}

local function record(entry)
    local log = Trace._log
    log[#log + 1] = entry
    while #log > Trace._limit do
        table.remove(log, 1)
    end
end

--- Build a compact description of the matched rule.
---
--- `matched` is a table when a route matched, `false` when routing ran and
--- found nothing, and `nil` when routing never happened.  All three reach the
--- hooks, so check the type before indexing — indexing a boolean raises, and a
--- raising hook is swallowed by the bus (the request still succeeds, but the
--- trace silently loses its field).
local function describe(matched)
    if matched == nil then
        return "none"
    end
    if type(matched) ~= "table" then
        return "no-route"
    end

    local methods = type(matched.method) == "table"
        and table.concat(matched.method, ",")
        or tostring(matched.method)
    return methods .. " " .. tostring(matched.path or matched.responser or "?")
end

--- Hooks registered on the plugin table.
Trace.hooks = {

    on_boot = function(app)
        app.logger:debug("request_trace: on_boot (master phase)")
    end,

    on_worker_init = function(app)
        -- Per-worker state belongs here: the master phase has no workers and no
        -- request context.
        app.logger:debug("request_trace: on_worker_init (pid ",
            tostring(ngx.worker.pid()), ")")
    end,

    on_request = function(app, ctx)
        -- First hook with a request scope.  Resolve request-scoped services from
        -- `ctx`; `app` holds worker-scoped singletons.
        local req = ctx:make("request")
        record({
            started_at = ngx.now(),
            ip         = req.remote_addr,
            method     = req.method,
            uri        = req.path_info,
        })
    end,

    on_dispatch = function(app, ctx, matched, router)
        -- The route is validated and about to run: a natural place for
        -- per-route metrics or an access log entry with the resolved target.
        local entry = Trace._log[#Trace._log]
        if entry then
            entry.route = describe(matched)
        end
    end,

    on_response = function(app, ctx, response)
        local entry = Trace._log[#Trace._log]
        if entry then
            -- on_response fires after the body is sent, so the status is final.
            entry.status = response and response.get_status
                and response:get_status()
                or (response and response.status)
                or 200
            entry.ms = math.floor((ngx.now() - (entry.started_at or ngx.now())) * 1000)
        end
    end,

    on_error = function(app, ctx, exception, matched)
        -- Handler errors are caught by the dispatcher, so this is where they
        -- surface to a plugin.  `exception` is a structured Exception object.
        local entry = Trace._log[#Trace._log]
        if entry then
            entry.failed = {
                layer   = exception and exception.layer,
                status  = exception and exception.status,
                message = exception and exception.message,
            }
        end

        app.logger:error("request_trace: ",
            tostring(exception and exception.layer), " error on ",
            describe(matched), ": ",
            tostring(exception and exception.message))
    end,
}

--- Read the recorded traces.  Used by the /traces route.
function Trace.entries()
    local out = {}
    for i, e in ipairs(Trace._log) do
        out[i] = e
    end
    return out
end

return Trace
