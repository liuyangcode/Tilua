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
