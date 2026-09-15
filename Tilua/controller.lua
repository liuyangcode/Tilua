---@class controller
---
---
local class = require("Tilua.utils.class")
local controller = class()

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

function controller:assign(...)
    self.ctx.view:assign(...)
end

function controller:display(template_file)
    local ctx = self.ctx
    if not template_file then
        template_file = self.controller .. '/' .. self.action
    end
    return ctx.response:render(template_file)
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

return controller


