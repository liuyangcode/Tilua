local class = require("pl.class")
local cjson = require "cjson"
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

function controller:ajax_return(data, type)
    type = type or app:C('default_ajax_return')
    type = string.upper(type)
    if type == 'JSON' then
        ngx.header.content_type = "application/json;chartset=uft-8"
        ngx.say(cjson.encode(data))
    elseif type == 'JSONP' then
        ngx.header.content_type = "application/json;chartset=uft-8"
        ngx.say(cjson.encode(data))
    end
end

function controller:display(template_file)
    local ctx = self.ctx
    local mvc = ctx.midware.mvc
    if not template_file then
        template_file = mvc.controller_name .. '/' .. mvc.action_name .. '.html'
    end
    return ctx.view:render(template_file)
end

function controller:_call()
    --魔术方法
end

return controller

