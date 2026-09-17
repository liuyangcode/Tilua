--- Configuration for `App.status = "dev"`.
---
--- Layering (later wins):
---   Tilua/config/default.lua -> Api/config/default.lua -> Api/config/<status>.lua
return {
    app_title   = "Tilua Api example",
    api_version = "1.0.0",

    -- Token expected by Api/middleware/api_token.lua.
    -- In a real app read this from the environment, never hard-code it.
    api_token = "secret",

    log = { type = "stderr", level = "DEBUG" },

    -- No Redis, no HTML cache: this example is self-contained.
    html_cache = false,

    -- Must match a lua_shared_dict in nginx.conf.
    SHDICIT_NAME = "api_cache",

    route = {},

    --- Convention-based controller routes.
    ---
    --- With this on, `App:boot_worker()` scans `Api/controller/` and registers a
    --- route per public action, so `Api/controller/demo.lua` is reachable at
    --- GET /demo/hello and GET /demo/echo/{word} WITHOUT any entry in routes.lua.
    ---
    --- Explicit routes always win over a discovered route for the same method and
    --- path, so this is additive.  Try: curl http://localhost:8081/demo/hello
    auto_routes = true,

    --- Should actions with NO route annotation be registered too?
    ---
    ---   true  (default) `Demo:hello` carries no annotation and is still exposed
    ---                   as GET /demo/hello
    ---   false           only actions carrying `@get` / `@post` / `@route` are
    ---                   exposed; unannotated ones are skipped and listed in the
    ---                   discovery report
    ---
    --- Flip it to false and `curl -i http://localhost:8081/demo/hello` returns
    --- 404 while `/demo/echo/hi` and `/demo/secure` keep working.  Use it when you
    --- want the controller to be the complete, explicit list of endpoints.
    auto_routes_unannotated = true,

    --- Plugins. Each entry is a module name (required and registered) or a table.
    ---
    --- `Api/plugin/request_trace.lua` records a per-request trace via the
    --- framework hooks and exposes it at GET /traces -- see that file for the
    --- full hook contract.
    plugins = {
        "Api.plugin.request_trace",
    },

    --- Middleware by OpenResty phase.
    ---
    ---   body_parser -> parses JSON/form bodies into request.body. Must run
    ---                  before any handler that reads a body.
    ---   request_id  -> content-phase decorator from Api/middleware/.
    ---
    --- The access guard is NOT listed here: it is declared per route so only
    --- /admin/stats is gated.  A global access guard would gate every route.
    middleware_phases = {
        rewrite = {},
        access  = {},
        content = { "body_parser", "request_id" },
    },
}
