--- Api — a realistic JSON service.
---
--- Demonstrates the parts you reach for once "hello world" is not enough:
---   * application services registered in the IoC container
---   * middleware split across OpenResty phases (access guard, request id)
---   * declarative parameter validation
---   * structured error responses
---   * JSON request bodies
---   * per-route middleware vs global middleware
---   * request-scoped state that is released at the end of the request
---
--- Everything is in-memory so the example runs with no Redis or MySQL.

local route  = require("Tilua.http.router")
local errors = require("Tilua.core.errors")

--- Global middleware: applies to every request.
---
--- Declared in config (see config/dev.lua) so nothing is hidden here, except
--- this one, which is registered inline to show the alternative.
route.group(function()
    --- ---------------------------------------------------------------
    --- Public routes
    --- ---------------------------------------------------------------

    route.get("/", function(ctx)
        local cfg = ctx:make("config")
        return {
            service = cfg.app_title,
            version = cfg.api_version,
            endpoints = {
                "GET    /health",
                "GET    /todos",
                "POST   /todos",
                "GET    /todos/{id}",
                "DELETE /todos/{id}",
                "GET    /echo/{mode}      (mode: in,upper,lower)",
                "GET    /admin/stats      (requires X-Api-Token)",
            },
        }
    end)

    --- A Lua table returned from a handler is JSON-encoded automatically, so
    --- `return { ... }` is all a JSON endpoint needs.
    route.get("/health", function(ctx)
        return {
            status = "ok",
            pid    = ngx.worker.pid(),
            request_id = ctx.request_id,
        }
    end)

    route.get("/todos", function(ctx)
        return { items = ctx:make("todo_store"):all() }
    end)

    --- Reading a JSON body.
    ---
    --- `body_parser` middleware (see config/dev.lua) parses the body into
    --- `request.body` before the handler runs.
    route.post("/todos", function(ctx)
        local request = ctx:make("request")
        local store   = ctx:make("todo_store")

        local title = request:input("title")
        if not title then
            -- Structured errors render as JSON with the right status code.
            return errors.bad_request("`title` is required", "missing_title")
        end

        return store:add(title)
    end)

    --- ---------------------------------------------------------------
    --- Parameter validation
    --- ---------------------------------------------------------------
    ---
    --- The third whitespace-separated field of a rule key is a validation spec:
    ---     <param>:<op>,<value>[;<param>:<op>,<value>]
    ---
    --- ops: reg (regex), eq, neq, in, notin
    ---
    --- A request that fails validation is treated as "no route matched" and
    --- falls through to 404 -- the handler never runs.
    route["get /todos/{id} id:reg,^[0-9]+$"] = function(ctx, id)
        local todo = ctx:make("todo_store"):get(tonumber(id))
        if not todo then
            return errors.not_found("no todo with id " .. tostring(id))
        end
        return todo
    end

    route["delete /todos/{id} id:reg,^[0-9]+$"] = function(ctx, id)
        local ok = ctx:make("todo_store"):remove(tonumber(id))
        if not ok then
            return errors.not_found("no todo with id " .. tostring(id))
        end
        return { deleted = tonumber(id) }
    end

    --- Validation on a path parameter with a list of allowed values.
    ---
    --- `in` / `notin` take a comma-separated list.  A value outside the list is
    --- treated as "no route matched" -> 404, so the handler never sees it.
    route["get /echo/{mode} mode:in,upper,lower"] = function(ctx, mode)
        local text = ctx:make("request"):input("text") or "hello"
        return {
            mode     = mode,
            input    = text,
            output   = mode == "upper" and text:upper() or text:lower(),
        }
    end

    --- ---------------------------------------------------------------
    --- Route-scoped access middleware
    --- ---------------------------------------------------------------
    ---
    --- `nil` is the content-phase middleware list; the 4th argument declares
    --- middleware for other phases.  Declaring the guard here means it gates
    --- only this route, not every route in the app.
    route.get("/admin/stats", function(ctx)
        return {
            todos    = ctx:make("todo_store"):count(),
            uptime_s = math.floor(ngx.now() - ctx:make("boot_time")),
        }
    end, nil, { phases = { access = { "api_token" } } })
end)
