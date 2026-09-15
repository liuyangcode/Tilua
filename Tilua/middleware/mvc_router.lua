local lw_util = require("Tilua.utils.util")
local helpers = require("Tilua.core.helpers")
local split = helpers.split
local strip = helpers.strip
local table_concat = table.concat

local callable = lw_util.callable
local base = require("Tilua.middleware.base")
---@class mvc
local mvc_router = (type(base.define) == "function" and base.define()) or base
mvc_router.alias = "mvc"


local default_config = {
    default_controller = "index",
    default_action = "index",
    controller_layer = "controller",
}

function mvc_router:handle(next_fn, ...)
    local ctx = self.ctx
    local request = ctx:unpack()
    ctx.logger:debug("Mvc router middleware start route path ", request.routed_uri)
    local pathinfo = request.routed_uri or ""
    local parts = split(strip(pathinfo, "/"), "/", true)
    local cleaned = {}
    for _, p in ipairs(parts) do
        if p ~= "" then
            cleaned[#cleaned + 1] = p
        end
    end
    local controller = cleaned[1]
    local action = cleaned[2]
    local params = {}
    for i = 3, #cleaned do
        params[#params + 1] = cleaned[i]
    end

    self.controller_name = not lw_util.empty(controller) and controller or self.config.default_controller
    self.action_name = not lw_util.empty(action) and action or self.config.default_action
    local handler = lw_util.import(
        self.ctx.name,
        self.config.controller_layer,
        self.controller_name
    )
    ctx.logger:debug(
        "Mvc router middleware end route controller:",
        self.ctx.name,
        self.config.controller_layer,
        self.controller_name
    )

    if handler then
        self.controller = handler(self.ctx)
        if callable(self.controller[self.action_name]) and string.sub(self.action_name, 1, 1) ~= "_" then
            self.action = self.controller[self.action_name]
            ctx.logger:debug(
                "Mvc router middleware end route controller:",
                self.controller_name,
                " action:",
                self.action_name
            )
        elseif callable(self.controller._call) then
            ctx.logger:debug("Mvc router middleware end route controller:", self.controller_name, " action:_call")
            self.action = self.controller._call
        end
        self.ctx.dispatcher:to_handler(function()
            return self.action(self.controller, self.ctx, table.unpack(params))
        end)
    else
        local errors = require("Tilua.core.errors")
        self.ctx.dispatcher:to_handler(function()
            return errors.not_found()
        end)
    end
    return next_fn(...)
end

function mvc_router:_construct(ctx, config)
    self.config = helpers.extend({}, default_config)
    if config then
        helpers.extend(self.config, config)
    end
end

return mvc_router
