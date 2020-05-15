local lw_util = require('Tilua.util')
local pl_utils = require('pl.utils')

local stringx = require "pl.stringx"
local split = stringx.split
local strip = stringx.strip
local table_concat = table.concat
local update = require("pl.tablex").update

local callable = lw_util.callable
---@class mvc
local mvc_router = require "Tilua.midware" .derive()
mvc_router.alias = 'mvc'

local default_config = {
    default_controller = 'index',
    default_action = 'index',
    view_layer = 'view',
    controller_layer = 'controller',
    model_layer = 'model'
}

function mvc_router:_init(ctx, config)
    self.config = update(default_config,config or {})
    self:super(ctx)
end

function mvc_router:handle(next, ...)
    local request = self.ctx:unpack()
    local pathinfo = request.get_routed_uri()
    local controller, action, params = (function
    (controller, action, ...)
        return controller, action, { ... }
    end)(table.unpack(split(strip(pathinfo, '/'), '/')))

    self.controller_name = not lw_util.empty(controller) and controller or self.config.default_controller
    self.action_name = not lw_util.empty(action) and action or self.config.default_action
    local found, hanlder = pcall(require, table_concat({
        self.ctx.app_name,
        self.config.controller_layer,
        self.controller_name
    }, '.'))

    if found then
        self.controller = hanlder(self.ctx)
        if rawget(hanlder, self.action_name) and callable(self.controller[self.action_name]) and string.sub(self.action_name, 1, 1) ~= '_' then
            self.action = self.controller[self.action_name]
        elseif callable(self.controller._call) then
            self.action = self.controller._call
        end
        self.ctx.dispatcher:to_handler(pl_utils.bind1(self.action, self.controller))
    else
        self.ctx.dispatcher:to_handler(function(ctx)
            ctx.response.body = 'found no responser for route:' .. pathinfo
        end)
    end
    return next(...)
end

return mvc_router