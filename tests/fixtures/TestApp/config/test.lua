--- Fixture config for TestApp.
return {
    app_title = "Container Demo",
    route = {},
    health_path = "/healthz",
    log = { type = "stderr", level = "DEBUG" },
    -- No GLOBAL access middleware here on purpose: a global access guard would
    -- gate every route.  The admin guard is declared per-route instead
    -- (see routes.lua), which is what a real app wants.
    middleware_phases = {
        access = {},
    },
}
