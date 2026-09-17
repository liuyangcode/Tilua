--- Fixture controller for discovery tests.
---
--- `index` / `show` / `greet` are targets; `_helper` and `_internal` are private
--- (leading underscore) and must NOT become routes.  The inherited helpers from
--- the framework controller base (`assign` / `display` / `service` / `model` /
--- `fail` / `_call`) must not either.

local controller = require("Tilua.controller")

local Widget = controller.define()

function Widget:index()
    return "Widget:index"
end

function Widget:show(id)
    return "Widget:show:" .. tostring(id)
end

function Widget:greet(name)
    return "Widget:greet:" .. tostring(name)
end

--- Private by convention: leading underscore.
function Widget:_helper()
    return "private"
end

return Widget
