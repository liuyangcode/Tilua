---@class controller
---
---
local class = require("Tilua.utils.class")
local controller = class()

function controller:_construct(ctx)
    ---@type app
    self.ctx = ctx
    return self
end

function controller:assign(...)
    self.ctx.view:assign(...)
end

function controller:display(template_file)
    local ctx = self.ctx
    if not template_file then
        local mvc = ctx.midware.mvc
        template_file = mvc.controller_name .. '/' .. mvc.action_name
    end
    return ctx.response:render(template_file)
end

function controller:_call()
    return 404
end

return controller

