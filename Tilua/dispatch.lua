local ngx = ngx
local class = require("pl.class")
local tablex = require "pl.tablex"
local lw_util = require('Tilua.util')
local pl_utils = require('pl.utils')
local string_find = string.find
---@class dispatch
local dispatch = class()

function dispatch:_init(app)
    ---@type app
    self.ctx = app
end

function dispatch:prepare_ctx_args_for_responser(args)
    return self.ctx, table.unpack(args)
end

---make_chain_call
---@param midware table
---@param handler function
function dispatch:make_chain_call(midware, handler, ...)
    local mid
    local args = { ... } --参数绑定
    local next = function
    ()
        local resp = handler(self:prepare_ctx_args_for_responser(args))
        local async_mid = {}
        if midware.aftermidware then
            for i = 1, #midware.aftermidware do
                async_mid[#async_mid + 1] = self.ctx.manager.instance(midware.aftermidware[i])
            end
            if #async_mid > 0 then
                resp:after_send(function()
                    tablex.map(function(asyc_midware)
                        pl_utils.bind1(asyc_midware.handle, asyc_midware)(self.ctx)
                    end, async_mid)
                end)
            end
        end
        return resp
    end
    --初始化响应前中间件
    return tablex.reduce(function(res, next_midware)
        mid = self.ctx.midware.instance(next_midware)
        local func = pl_utils.bind1(mid.handle, mid)
        return function(...)
            return func(table.unpack({
                res,
                table.unpack(args)
            }))
        end
    end, lw_util.reverseTable(midware.beforemidware or {}), next)
end

---run
---@param router table
function dispatch:run(router)
    if lw_util.is_array(router) then
        local hanlder, params, midware = table.unpack(router)
        if lw_util.is_string(hanlder) then
            local responser = hanlder
            hanlder = function(...)
                return self:get_handler(responser)(...)
            end
        end
        return self:make_chain_call(midware, hanlder, table.unpack(params or {}))
    end
    return self:make_chain_call({}, function(...)
        return 'no matches route for path ' .. router
    end)
end

function dispatch:get_handler(hanlder)
    if string_find(hanlder, '@', 1, true) then
        local resp = pl_utils.split(hanlder, '@', true)
        local controller = resp[1]
        local action = resp[2]
        if not string_find(controller, self.ctx.app_name .. '.') then
            controller = self.ctx.app_name .. '.' .. controller
        end
        local responser = lw_util.prequire(controller)
        if responser then
            return responser[action]
        end
    end
    return self.hanlder
end

---设置responser
---@param handler function
function dispatch:to_handler(handler)
    self.hanlder = handler
end

return dispatch
