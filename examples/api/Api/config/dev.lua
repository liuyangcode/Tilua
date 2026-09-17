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
