local class = require("pl.class")
local cjson = require "cjson"
local app = ngx.ctx.app_context
---@class controller
local controller = class()
function controller:_init(ctx)
    ---@type app
    self.app = ctx
end

function controller:get_view()
    if self.view then
        return self.view
    end
    self.view = require "Tilua.view"(self.app)
    return self.view
end

function controller:assign(...)
    self:get_view():assign(...)
end

function controller.derive()
    return class(controller)
end

function controller:set_header(name, value)
    ngx.header[name] = value
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
    if not template_file then
        template_file = app.mvc_router.controller_name .. '/' .. app.mvc_router.action_name .. '.html'
    end
    self.app.response.body = self:get_view():render(template_file)
end

function controller:_call()
    --魔术方法
end

return controller

