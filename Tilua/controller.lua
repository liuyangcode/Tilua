local class = require("pl.class")
---@class controller
local controller = class()
function controller:_init(ctx)
    ---@type app
    self.ctx = ctx
end

function controller:assign(...)
    self.ctx.view:assign(...)
end

function controller.derive()
    return class(controller)
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
    --魔术方法
end

return controller

