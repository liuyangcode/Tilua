-- Minimal health-check style routes (example)
local route = require("Tilua.route")  -- shim → Tilua.http.router
local errors = require("Tilua.core.errors")

route.get("/health", function(ctx)
    return {
        status = "ok",
        time   = ngx.now(),
        pid    = ngx.worker.pid(),
    }
end)

route.get("/ready", function(ctx)
    -- extend with db/redis ping in real apps
    return { ready = true }
end)

route.get("/error-demo", function(ctx)
    return errors.not_found("resource missing", "demo_not_found")
end)
