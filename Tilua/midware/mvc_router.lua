local lw_util = require('Tilua.utils.util')

local stringx = require "pl.stringx"
local split = stringx.split
local strip = stringx.strip
local table_concat = table.concat
local update = require("pl.tablex").update

local callable = lw_util.callable
local base = require("Tilua.midware.base")
---@class mvc
local mvc_router = base.define()
mvc_router.alias = 'mvc'

local default_config = {
    default_controller = 'index',
    default_action = 'index',
    view_layer = 'view',
    controller_layer = 'controller',
    model_layer = 'model'
}

function mvc_router:handle(next, ...)
    local ctx = self.ctx
    local request = ctx:unpack()
    ctx.logger:debug("Mvc router midware start route path ", request.routed_uri)
    local pathinfo = request.routed_uri
    local controller, action, params = (function
    (controller, action, ...)
        return controller, action, { ... }
    end)(table.unpack(split(strip(pathinfo, '/'), '/')))

    self.controller_name = not lw_util.empty(controller) and controller or self.config.default_controller
    self.action_name = not lw_util.empty(action) and action or self.config.default_action
    local hanlder = lw_util.import(
            self.ctx.name,
            self.config.controller_layer,
            self.controller_name
    )
    ctx.logger:debug("Mvc router midware end route controller:", self.ctx.name,
            self.config.controller_layer,
            self.controller_name)

    if hanlder then
        self.controller = hanlder(self.ctx)
        if callable(self.controller[self.action_name]) and string.sub(self.action_name, 1, 1) ~= '_' then
            self.action = self.controller[self.action_name]
            ctx.logger:debug("Mvc router midware end route controller:", self.controller_name, " action:", self.action_name)
        elseif callable(self.controller._call) then
            ctx.logger:debug("Mvc router midware end route controller:", self.controller_name, " action:_call")
            self.action = self.controller._call
        end
        self.ctx.dispatcher:to_handler(function()
            return self.action(self.controller, self.ctx, table.unpack(params))
        end)
    else
        self.ctx.dispatcher:to_handler(function()
            return 404
        end)
    end
    return next(...)
end

function mvc_router:_construct(ctx, config)
    self.config = update(default_config, config or {})
end

return mvc_router