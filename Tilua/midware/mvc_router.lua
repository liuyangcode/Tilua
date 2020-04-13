
local lw_util = require('Tilua.util')
local pl_utils = require('pl.utils')

local stringx = require "pl.stringx"
local split = stringx.split
local strip = stringx.strip
local table_concat = table.concat

local callable = lw_util.callable
local mvc_router = require "Tilua.midware" .derive()

function mvc_router:handle(next, request, ...)
    local pathinfo = request.get_routed_uri()
    local module = self.app:get_module()
    local controller, action, params = (function
    (controller, action, ...)
        return controller, action, { ... }
    end)(table.unpack(split(strip(pathinfo, '/'), '/')))

    controller = not lw_util.empty(controller) and controller or self.default_controller
    action = not lw_util.empty(action) and action or self.default_action

    local controller_module = table_concat({
        self.app.app_name,
        module,
        self.controller_layer,
        controller
    }, '.')
    local found, hanlder = pcall(require, controller_module)
    if found then
        hanlder = hanlder(self.app)
        if callable(hanlder[action]) then
            action = hanlder[action]
        elseif callable(hanlder._call) then
            action = hanlder._call
        end
        self.app:get_dispatcher():to_handler(pl_utils.bind1(action, hanlder))
    else
        self.app:get_dispatcher():to_handler(function()
            return ('found no responser for route:' .. pathinfo)
        end)
    end
    return next(request, ...)
end
function mvc_router:_init(app)
    self:super(app)
    self.default_controller = "index"
    self.default_action = "index"
    self.default_module = 'Home'

    self.view_layer = "view"
    self.controller_layer = "controller"
    self.model_layer = "model"
end
return mvc_router