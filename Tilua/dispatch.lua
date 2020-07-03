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
---make_chain_call
---@param midware table
---@param handler function
function dispatch:make_chain_call(midware, handler)
    local mid
    local next = function
    ()
        return self:prepare_response(handler())
    end
    --初始化响应前中间件
    return tablex.reduce(function(res, next_midware)
        mid = self.ctx.midware.instance(next_midware)
        local func = pl_utils.bind1(mid.handle, mid)
        return function(...)
            return func(res, ...)
        end
    end, lw_util.reverseTable(midware or {}), next)
end

function dispatch:prepare_response(...)
    local res1 = select(1, ...)
    local res2 = select(2, ...)
    local res3 = select(3, ...)
    local res4 = select(4, ...)
    local response = self.ctx.response
    local tresponse = type(res1)
    local tcontext = type(res2)

    if res4 or tcontext =='boolean' then
        response:jump(...)
    elseif tresponse == 'number' then
        -- return http status code like 404,500
        response.status = res1
    elseif not response.body then
        -- response does not have body to send
        if tresponse == 'table' then
            if #res1 == 2 and type(res1[1]) == 'string' and type(res1[2]) == 'table' then
                -- return view like {view,context}
                response:render(res1[1], res1[2])
            elseif not res1.new then
                --retun a table but not a response instance
                response.body = res1
            end
        elseif tresponse == 'string' then
            response:render(res1, res2 or {})
        end
    end
    return response
end

function dispatch:create_responser(router)
    local hanlder, args
    local midware = {}
    if lw_util.is_array(router) then
        hanlder, args, midware = table.unpack(router)
        local thandler = type(hanlder)
        if thandler == 'string' then
            self.handler = function(...)
                return self:get_handler(hanlder, args)()
            end
        elseif lw_util.callable(hanlder) then
            self.handler = function
            ()
                return hanlder(self.ctx, table.unpack(args))
            end
        end
    end
    return self:make_chain_call(midware, self.handler or function(...)
        return 404
    end)
end
---run
---@param router table
function dispatch:run(router)
    local responser = self:create_responser(router)
    return self:prepare_response(responser())
end

function dispatch:get_handler(hanlder, args)
    if string_find(hanlder, '@', 1, true) then
        local resp = pl_utils.split(hanlder, '@', true)
        local controller = resp[1]
        local action = resp[2]
        if not string_find(controller, self.ctx.name .. '.') then
            controller = self.ctx.name .. '.' .. controller
        end
        local responser = lw_util.prequire(controller)
        if responser then
            return function
            ()
                return responser[action](self.ctx, table.unpack(args))
            end
        end
    end
    return self.handler or function
    ()
        return 404
    end
end

---设置responser
---@param handler function
function dispatch:to_handler(handler)
    self.handler = handler
end

function dispatch.derive()
    return class(dispatch)
end

return dispatch
