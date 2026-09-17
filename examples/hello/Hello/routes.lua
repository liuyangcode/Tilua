--- Hello — the smallest useful Tilua application.
---
--- Demonstrates the whole request flow in four routes:
---   /            renders a view (Tilua.template)
---   /hello/{name} path parameter + plain-text response
---   /api/ping    a Lua table returned as JSON
---   /boom        what a crashing handler looks like to a client
---
--- Read the comments top-to-bottom; each block is one concept.

local route    = require("Tilua.http.router")     -- route registration
local response = require("Tilua.http.response")   -- helper to build a response

--- 1. A view.
---
--- Returning `("index", context)` means "render view/index.html with this
--- context".  The template engine escapes `{{ ... }}` but not `{{{ ... }}}`,
--- and its paths resolve relative to this app's directory.
route.get("/", function(ctx)
    return "index", {
        app_name = ctx:make("config").app_title,
        message  = "Your Tilua app is running.",
    }
end)

--- 2. A path parameter.
---
--- `{name}` captures one URL segment.  The handler receives the captured value
--- as a positional argument, in the order the parameters appear in the path.
route.get("/hello/{name}", function(ctx, name)
    return response("Hello, " .. tostring(name) .. "!")
end)

--- 3. JSON.
---
--- Returning a plain table is encoded as JSON automatically (the dispatcher
--- calls response:json).  No manual encoding, no content-type juggling.
route.get("/api/ping", function()
    return { pong = true, pid = ngx.worker.pid() }
end)

--- 4. A failing handler.
---
--- `error(...)` anywhere in a handler is caught by the framework, logged with a
--- request id, and turned into a structured JSON error.  In production the
--- message is replaced by a generic one; in dev you see the real message.
route.get("/boom", function()
    error("this route always fails -- try /delete-me from the layout")
end)
