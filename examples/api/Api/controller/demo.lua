--- Fixture controller for the api example, used to demonstrate `auto_routes`
--- and action annotations.
---
--- With `auto_routes = true` in the config, worker boot discovers this file and
--- registers the routes below WITHOUT any routes.lua entry.  `hello` has no
--- annotation and keeps the convention default `GET /demo/hello`; the others
--- declare their method and middleware inline with `@<verb>` annotations.

local controller = require("Tilua.controller")

local Demo = controller.define()

--- Unannotated: discovered as GET /demo/hello.
function Demo:hello()
    return { discovered = true, controller = "demo", action = "hello" }
end

--- A path parameter, and the same path for a second method.
--- @get  /demo/echo/{word}
--- @post /demo/echo
function Demo:echo(word)
    return { word = tostring(word), discovered = "annotated" }
end

--- No path: falls back to the convention route GET /demo/from_verb.
--- @get
function Demo:from_verb()
    return { note = "the path is optional for @get" }
end

--- Access-phase middleware declared inline.
--- @get /demo/secure
--- @phases access = api_token
function Demo:secure()
    return { secured = true, note = "guarded by the access phase" }
end

--- Content-phase middleware declared inline.
--- @get /demo/traced
--- @middleware request_id
function Demo:traced()
    return { traced = true, note = "content-phase middleware from an annotation" }
end

--- Three verbs on one path.
--- @get  /demo/methods
--- @post /demo/methods
--- @put  /demo/methods
function Demo:methods()
    return { methods = "GET, POST and PUT all reach here" }
end

--- Private: leading underscore, so discovery must skip it.
function Demo:_secret()
    return "should not be routable"
end

return Demo
