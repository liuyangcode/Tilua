--- Hello application entry point.
---
--- Every Tilua application is a subclass of the framework's Application class,
--- which is also an IoC container.

local App = require("Tilua.app").define()

--- These are CLASS fields, not instance fields.
---
--- Tilua's constructor reads them while building the instance, so assigning them
--- inside `_construct` (which runs later) would be too late.
---
---   name   must match the directory name -- it is the `require` prefix
---   status selects config/<status>.lua on top of config/default.lua
---   debug  true  -> verbose errors and template reloads
---          false -> generic 5xx messages (what you want in production)
App.name   = "Hello"
App.status = "dev"
App.debug  = true

--- Register your own services here.
---
--- The framework already binds config, logger, router, request, response, view,
--- cache, model and service.  Anything you add becomes available as
--- `ctx:make("name")` (or as a constructor argument via `container:call`).
---
--- Services registered with `singleton` live for the worker's lifetime;
--- `scoped` services are created per request and released by `flush()`.
function App:_construct(opts)
    self:singleton("greeter", function(c)
        return {
            greet = function(who)
                return "Hello, " .. tostring(who) .. "!"
            end,
        }
    end)

    --- An alias lets the same service be resolved under a second name.
    self:alias("greeter", "hello")

    return self
end

return App
