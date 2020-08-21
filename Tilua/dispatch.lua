local ngx = ngx
local class = require("Tilua.utils.class")
local tablex = require "pl.tablex"
local lw_util = require('Tilua.utils.util')
local pl_utils = require('pl.utils')
local string_find = string.find

local stringx = require "pl.stringx"
local split = stringx.split
local strip = stringx.strip

---@class dispatch
local dispatch = class.define()

---_construct
---@param app app
function dispatch:_construct(app)
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

    if res4 or tcontext == 'boolean' then
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

local function get_bind_args(router)
    local bind_args = {}
    if router.matcher == '~' then
        for i, v in ipairs(router.args) do
            if not string.match(v, '%d+') then
                table.insert(bind_args, router.vals[i])
            end
        end
    end
    local path_params = pl_utils.split(router.extra_path or '', '/')
    if #path_params > 0 then
        tablex.insertvalues(bind_args, path_params)
    end
    return bind_args
end

function dispatch:create_responser(router)
    local midwares = tablex.deepcopy(router.midware)
    local handler = router.responser
    local thandler = type(handler)
    if thandler == 'string' then
        self.handler = function(...)
            return self:find_handler(router)()
        end
    elseif thandler == 'function' then
        local bind_args = get_bind_args(router)
        self.handler = function
        ()
            return handler(self.ctx, table.unpack(bind_args))
        end
    end
    return self:make_chain_call(midwares, self.handler or function(...)
        return 404
    end)
end
---run
---@param router table
function dispatch:run(matched, router)
    local responser = nil
    if matched then
        responser = self:create_responser(router)
    else
        responser = function
        ()
            return 404
        end
    end
    return self:prepare_response(responser())
end

---find_responser
---@param router table
function dispatch:find_handler(router)
    local responser = router.responser
    ---responser is a string like controller.Index@index ....
    if string_find(responser, '@', 1, true) then
        local resp = pl_utils.split(responser, '@', true)
        local controller = resp[1]
        local action = resp[2]
        if not string_find(controller, self.ctx.name .. '.') then
            controller = self.ctx.name .. '.' .. controller
        end
        local handler = lw_util.import(controller)
        local bind_args = get_bind_args(router)
        if handler and type(handler[action]) == 'function' then
            return function
            ()
                return handler[action](self.ctx, pl_utils.unpack(bind_args))
            end
        end
    else
        ---mvc mode /Index/index/.... controller Index  action index ,etc
        local controller, action, params = (function
        (controller, action, ...)
            return controller, action, { ... }
        end)(table.unpack(split(strip(router.path .. router.extra_path, '/'), '/')))
        controller = controller or 'index'
        action = action or 'index'
        local handler = lw_util.import(self.ctx.name, 'controller', controller)
        if  handler then
            if handler._construct then
                handler = handler(self.ctx, controller, action)
            end
            if not handler.__parent[action] and type(handler[action]) == 'function' then
                return function
                ()
                    return handler[action](handler, self.ctx, pl_utils.unpack(params))
                end
            elseif type(handler._call) =='function' then
                return function
                ()
                    return handler._call(handler, self.ctx, pl_utils.unpack(params))
                end
            end
        end
    end
    return function
    ()
        return 404
    end
end

return dispatch
