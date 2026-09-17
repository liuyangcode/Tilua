--- Configuration for `App.status = "dev"`.
---
--- Layering (later wins):
---   1. Tilua/config/default.lua      framework defaults
---   2. Hello/config/default.lua      this app's defaults (not present here)
---   3. Hello/config/dev.lua          this file
---
--- See Tilua/config/default.lua for every available option.
return {
    app_title = "Hello Tilua",

    --- Log to stderr instead of a file: nothing to create, nothing to chmod,
    --- and the output lands in the same stream as `tilua serve` / docker logs.
    log = { type = "stderr", level = "DEBUG" },

    --- The framework default turns on an HTML cache and a Redis-backed data
    --- cache.  Both are off so this example runs with no external services.
    html_cache = false,

    --- Must match a `lua_shared_dict` declared in nginx.conf.
    SHDICIT_NAME = "hello_cache",

    --- Extra route rules declared as config rather than in routes.lua.
    --- The key is "<method> <path>", optionally followed by validation.
    route = {
        ["get /from-config"] = function()
            return { source = "config.route" }
        end,
    },

    --- Middleware, grouped by the OpenResty phase it runs in.
    ---
    ---   rewrite -> early short-circuiting (caching)
    ---   access  -> admission control (auth, rate limits); may deny
    ---   content -> default home (body parsing, sessions, MVC)
    ---
    --- This example needs none of them, so the list is empty. It is written out
    --- explicitly to show where they would go.
    middleware_phases = {
        rewrite = {},
        access  = {},
        content = {},
    },
}
