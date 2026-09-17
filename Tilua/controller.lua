---@class controller
---
---
local class = require("Tilua.utils.class")
local controller = class()

--- Methods the framework itself defines on a controller.
---
--- Route discovery uses this to tell framework API from application actions:
--- only NON-listed methods become routes.  It lives here, next to the
--- definitions, so adding a method above and forgetting this list is a visible
--- mistake rather than a silent leak — `tests/test_mvc_pipeline.lua` asserts
--- that every function on this table is accounted for.
---
--- (It leaked once: `get` and `mount_context` were added without updating the
--- copy that lived in the discovery module, which published `/widget/get` and
--- `/widget/mount_context` as routes.)
controller.framework_methods = {
    _construct      = true,
    _call           = true,
    assign          = true,
    get             = true,
    mount_context   = true,
    display         = true,
    service         = true,
    model           = true,
    fail            = true,
    -- Injected by the class system into every derived class, not an action.
    define          = true,
    framework_methods = true,
}

---_construct
---@param ctx app
---@param controller_name string
---@param action_name string
function controller:_construct(ctx,controller_name,action_name)
    ---@type app
    self.ctx = ctx
    self.controller = controller_name
    self.action = action_name
    return self
end

--- Assign a value into the view context.
---
--- `self:assign(name, value)` or `self:assign{ a = 1, b = 2 }`.
function controller:assign(...)
    self.ctx.view:assign(...)
end

--- Read a value back out of the view context.  `nil` when absent.
function controller:get(name)
    return self.ctx.view:get(name)
end

--- Provide a fallback value for the view context.
---
--- Mounted values sit BENEATH assigned ones and beneath the table passed to
--- `display`, so they are the "defaults" of a render.  Delegating this as well
--- as `assign` is what lets the two be combined:
---
---     self:mount_context("site", config.site_name)   -- every view gets this
---     self:assign("title", "Home")                   -- this view only
---     return self:display("index", { items = items })
function controller:mount_context(name, value)
    self.ctx.view:mount_context(name, value)
    return self
end

--- Render a template and return the RESPONSE object.
---
--- `template_file` defaults to `<controller>/<action>`, which resolves under the
--- app's `view/` directory (so `index/index` -> `view/index/index.html`).
---
--- `context` is optional and is MERGED over whatever `assign` already set, so
--- both this and
---
---     self:assign("title", "Hi")
---     return self:display("index", { items = items })
---
--- work.  The second argument used to be ignored: `display` took only the
--- template name, so a passed context was silently dropped and the template
--- rendered with `nil` for every key it expected.
---
--- Returns the response (not a string), because `view:render` goes through
--- `response:render`.  The rendered HTML is on `response.body`.
function controller:display(template_file, context)
    local ctx = self.ctx
    if not template_file then
        template_file = self.controller .. '/' .. self.action
    end
    return ctx.response:render(template_file, context)
end

function controller:_call()
    return 404
end

--- Business service: self:service("User") or self:service().User
function controller:service(name)
    local svc = self.ctx.service
    if not name then
        return svc
    end
    return svc[name]
end

--- Model shortcut
function controller:model(name)
    if not name then
        return self.ctx.model
    end
    return self.ctx.model[name]
end

function controller:fail(message, status, details)
    local Exception = require("Tilua.core.exception")
    error(Exception.controller(message, status or 500, details), 0)
end

return controller


