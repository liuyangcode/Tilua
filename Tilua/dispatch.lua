local ngx = ngx
local class = require("pl.class")
local tablex = require "pl.tablex"
local response = require('Tilua.response')
local lw_util = require('Tilua.util')
local pl_utils = require('pl.utils')
---@class dispatch
class.dispatch()

function dispatch:_init(app)
    self.app = app
end

function dispatch:prepare_ctx_args_for_responser(args)
    return self.app, response(), table.unpack(args)
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
                local ok, midware_class = pcall(require, midware.aftermidware[i][1])
                if not ok then
                    assert(false, 'midware named' .. midware.aftermidware[i][1] .. ' not found')
                end
                async_mid[#async_mid + 1] = midware_class(self.app,midware.aftermidware[i][2])
            end
            if #async_mid > 0 then
                resp:after_send(function()
                    ngx.eof() --返回终端
                    --异步执行代码
                    ngx.timer.at(500, function()
                        tablex.map(function(asyc_midware)
                            pl_utils.bind1(asyc_midware.handle, asyc_midware)(table.unpack({
                                resp,
                                table.unpack(args)
                            }))
                        end, async_mid)
                    end)
                end)
            end
        end
        return resp
    end

    --初始化响应前中间件
    return tablex.reduce(function(res, next_midware)
        local ok, midware_class = pcall(require, next_midware[1])
        if not ok then
            assert(false, 'midware named' .. next_midware[1] .. ' not found')
        end
        mid = midware_class(self.app,next_midware[2])
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
            hanlder = function(...)
                return self:get_handler()(...)
            end
        end
        return self:make_chain_call(midware, hanlder, table.unpack(params.args or {}))
    end
    return self:make_chain_call({}, function(...)
        return 'no matches route for path ' .. router
    end)
end

function dispatch:get_handler()
    return self.hanlder
end

---设置responser
---@param handler function
function dispatch:to_handler(handler)
    self.hanlder = handler
end

return dispatch
