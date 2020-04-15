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
    local controller, action, params = (function
    (controller, action, ...)
        return controller, action, { ... }
    end)(table.unpack(split(strip(pathinfo, '/'), '/')))

    self.controller_name = not lw_util.empty(controller) and controller or self.config.default_controller
    self.action_name = not lw_util.empty(action) and action or self.config.default_action
    local found, hanlder = pcall(require, table_concat({
        self.app.app_name,
        self.config.controller_layer,
        self.controller_name
    }, '.'))

    if found then
        self.controller = hanlder(self.app)
        if callable(self.controller[self.action_name]) then
            self.action = self.controller[self.action_name]
        elseif callable(self.controller._call) then
            self.action = self.controller._call
        end
        self.app.dispatcher:to_handler(pl_utils.bind1(self.action, self.controller))
    else
        self.app.dispatcher:to_handler(function(ctx,response)
            response.body = 'found no responser for route:' .. pathinfo
            return response
        end)
    end
    return next(request, ...)
end

function mvc_router:_init(app, config)
    self.config = config
    self:super(app)
    app.mvc_router = self
end
return mvc_router