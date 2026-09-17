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
    -- `greet` is a closure rather than method syntax: services returned from a
    -- container binding are plain tables, and callers reach them through more
    -- than one path (`self:service("greeter")`, `self:service().greeter`,
    -- `ctx:make("greeter")`).  Method syntax would make the result depend on
    -- which path was used.
    self:singleton("greeter", function(c)
        return {
            --- `who` is optional, so the original one-argument contract
            --- (`greet()` -> "hello <title>") still holds.
            greet = function(who)
                local base = "hello " .. tostring(c.config.app_title)
                if who == nil then
                    return base
                end
                return base .. ", " .. tostring(who)
            end,
        }
    end)

    self:alias("greeter", "hello")
    return self
end

return App
