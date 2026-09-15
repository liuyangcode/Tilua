--- Fixture application used by tests/test_app_container.lua
--- Demonstrates the container-first app style.

local App = require("Tilua.app").define()

--- Because Tilua's class system runs the parent `_construct` before ours,
--- anything the base constructor reads (`name`, `status`, `debug`) must be set
--- on the class before an instance is built.
App.name   = "TestApp"
App.status = "test"
App.debug  = true

--- Application-owned services, registered on top of the framework defaults.
--- The class chain consults the class table first, so `self.config` on the
--- instance resolves `App.config` unless a binding provides it — which is why
--- app-level bindings are registered lazily inside `_construct`.
function App:_construct(opts)
    -- base wiring already ran (Container._construct -> App._construct):
    -- container tables exist, loader set, framework bindings registered.
    self:singleton("greeter", function(c)
        return {
            greet = function()
                return "hello " .. tostring(c.config.app_title)
            end,
        }
    end)

    self:alias("greeter", "hello")
    return self
end

return App
