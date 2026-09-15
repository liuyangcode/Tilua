local ngx = ngx
local class = require("Tilua.utils.class")
local lw_util = require("Tilua.utils.util")
local helpers = require("Tilua.core.helpers")
local errors = require("Tilua.core.errors")
local string_find = string.find

local split = helpers.split
local strip = helpers.strip
local reverse = helpers.reverse
local bind1 = helpers.bind1
local reduce = helpers.reduce


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
    local next_fn = function()
        return self:prepare_response(handler())
    end
    local list = reverse(midware or {})
    return reduce(function(res, next_midware)
        local mid = self.ctx.midware.instance(next_midware)
        local func = bind1(mid.handle, mid)
        return function(...)
            return func(res, ...)
        end
    end, list, next_fn)
end

function dispatch:prepare_response(...)
    local res1 = select(1, ...)
    local res2 = select(2, ...)
    local res4 = select(4, ...)
    local response = self.ctx.response
    local tresponse = type(res1)
    local tcontext = type(res2)

    -- Structured TiluaError
    if errors.is_error(res1) then
        local as_json = self.ctx.config and self.ctx.config.enable_json_errors
        return errors.apply(response, res1, as_json)
    end

    if res4 or tcontext == "boolean" then
        response:jump(...)
    elseif tresponse == "number" then
        response.status = res1
    elseif not response.body then
        if tresponse == "table" then
            if #res1 == 2 and type(res1[1]) == "string" and type(res1[2]) == "table" then
                response:render(res1[1], res1[2])
            elseif not res1.new then
                response.body = res1
            end
        elseif tresponse == "string" then
            response:render(res1, res2 or {})
        end
    end
    return response
end

local function get_bind_args(router)
    local bind_args = {}
    if router.matcher == "~" then
        for i, v in ipairs(router.args or {}) do
            if not string.match(v, "%d+") then
                table.insert(bind_args, router.vals[i])
            end
        end
    end
    local path_params = split(router.extra_path or "", "/", true)
    -- drop empty segments from leading/trailing slash
    for _, p in ipairs(path_params) do
        if p ~= "" then
            table.insert(bind_args, p)
        end
    end
    return bind_args
end

local function shallow_copy_list(t)
    if not t then return {} end
    local r = {}
    for i, v in ipairs(t) do
        r[i] = v
    end
    return r
end

function dispatch:create_responser(router)
    local midwares = shallow_copy_list(router.midware)
    local handler = router.responser
    local thandler = type(handler)
    if thandler == "string" then
        self.handler = function(...)
            return self:find_handler(router)()
        end
    elseif thandler == "function" then
        local bind_args = get_bind_args(router)
        self.handler = function()
            return handler(self.ctx, table.unpack(bind_args))
        end
    end
    return self:make_chain_call(midwares, self.handler or function()
        return errors.not_found()
    end)
end

---run
---@param matched boolean
---@param router table
function dispatch:run(matched, router)
    local responser
    if matched then
        responser = self:create_responser(router)
    else
        responser = function()
            return errors.not_found()
        end
    end
    return self:prepare_response(responser())
end

---find_handler
---@param router table
function dispatch:find_handler(router)
    local responser = router.responser
    -- responser string like "controller.Index@index"
    if string_find(responser, "@", 1, true) then
        local resp = split(responser, "@", true)
        local controller = resp[1]
        local action = resp[2]
        if not string_find(controller, self.ctx.name .. ".", 1, true) then
            controller = self.ctx.name .. "." .. controller
        end
        local handler = lw_util.import(controller)
        local bind_args = get_bind_args(router)
        if handler and type(handler[action]) == "function" then
            return function()
                return handler[action](self.ctx, table.unpack(bind_args))
            end
        end
    else
        -- MVC path style /Index/index/...
        local parts = split(strip(router.path .. (router.extra_path or ""), "/"), "/", true)
        local cleaned = {}
        for _, p in ipairs(parts) do
            if p ~= "" then cleaned[#cleaned + 1] = p end
        end
        local controller = cleaned[1] or "index"
        local action = cleaned[2] or "index"
        local params = {}
        for i = 3, #cleaned do
            params[#params + 1] = cleaned[i]
        end
        local handler = lw_util.import(self.ctx.name, "controller", controller)
        if handler then
            if handler._construct then
                handler = handler(self.ctx, controller, action)
            end
            if handler.__parent and not handler.__parent[action] and type(handler[action]) == "function" then
                return function()
                    return handler[action](handler, self.ctx, table.unpack(params))
                end
            elseif type(handler._call) == "function" then
                return function()
                    return handler._call(handler, self.ctx, table.unpack(params))
                end
            elseif type(handler[action]) == "function" then
                return function()
                    return handler[action](handler, self.ctx, table.unpack(params))
                end
            end
        end
    end
    return function()
        return errors.not_found()
    end
end

return dispatch
