--- Tilua.http.dispatcher (v0.2.5)
--- Aligns handler return values with response:json / structured errors.

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

function dispatch:_construct(app)
    self.ctx = app
end

local function wants_json(ctx)
    if ctx.config and ctx.config.enable_json_errors then
        return true
    end
    local req = ctx.request
    if req and type(req.wants_json) == "function" then
        local ok, v = pcall(req.wants_json, req)
        if ok and v then
            return true
        end
    end
    return false
end

function dispatch:make_chain_call(midware, handler)
    local Exception = require("Tilua.core.exception")
    local next_fn = function()
        return self:prepare_response(handler())
    end
    local list = reverse(midware or {})
    return reduce(function(res, next_midware)
        local mid = self.ctx.midware.instance(next_midware)
        local func = bind1(mid.handle, mid)
        return function(...)
            local ok, out = xpcall(function(...)
                return func(res, ...)
            end, Exception.handler("middleware"), ...)
            if ok then
                return out
            end
            -- propagate Exception object
            return out
        end
    end, list, next_fn)
end

function dispatch:prepare_response(...)
    local res1 = select(1, ...)
    local res2 = select(2, ...)
    local res3 = select(3, ...)
    local res4 = select(4, ...)
    local response = self.ctx.response
    local tresponse = type(res1)
    local tcontext = type(res2)
    local as_json = wants_json(self.ctx)

    -- already the response object
    if tresponse == "table" and res1.send and res1.set_body then
        return res1
    end

    -- Structured TiluaError
    if errors.is_error(res1) then
        return errors.apply(response, res1, as_json)
    end

    -- jump(url, success, message, wait)
    if res4 or tcontext == "boolean" then
        response:jump(...)
        return response
    end

    -- bare status code
    if tresponse == "number" then
        if response.set_status then
            response:set_status(res1)
        else
            response.status = res1
        end
        -- optional message as body
        if type(res2) == "string" then
            if as_json then
                response:json({ error = { status = res1, message = res2 } }, res1)
            else
                response:set_body(res2)
            end
        elseif type(res2) == "table" and as_json then
            response:json(res2, res1)
        end
        return response
    end

    if response.body then
        return response
    end

    if tresponse == "table" then
        -- { "view", context } render form
        if #res1 == 2 and type(res1[1]) == "string" and type(res1[2]) == "table" then
            response:render(res1[1], res1[2])
        elseif res1.new then
            -- class-like table, ignore
        elseif as_json or (self.ctx.request and self.ctx.request.is_json and self.ctx.request:is_json()) then
            local status = (type(res2) == "number" and res2) or (response.status > 0 and response.status) or 200
            response:json(res1, status)
        else
            -- non-API: set as body (may auto-json if response supports table)
            response.body = res1
        end
    elseif tresponse == "string" then
        -- view name + context, or plain text when second is not table
        if tcontext == "table" or res2 == nil then
            if res2 == nil and as_json then
                response:text(res1)
            elseif tcontext == "table" then
                response:render(res1, res2)
            else
                response:render(res1, {})
            end
        else
            response:text(res1)
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
    for _, p in ipairs(path_params) do
        if p ~= "" then
            table.insert(bind_args, p)
        end
    end
    return bind_args
end

local function shallow_copy_list(t)
    if not t then
        return {}
    end
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

function dispatch:run(matched, router)
    local Exception = require("Tilua.core.exception")
    local responser
    if matched then
        responser = self:create_responser(router)
    else
        responser = function()
            return errors.not_found()
        end
    end
    local ok, result = xpcall(function()
        return self:prepare_response(responser())
    end, Exception.handler("controller"))
    if ok then
        -- prepare_response may return TiluaError without throwing
        if errors.is_error(result) or Exception.is(result) then
            local as_json = wants_json(self.ctx)
            return errors.apply(self.ctx.response, result, as_json ~= false)
        end
        return result
    end
    -- thrown exception
    local ex = Exception.is(result) and result or Exception.wrap(result, "controller")
    Exception.log(self.ctx, ex)
    return Exception.render(self.ctx.response, ex, self.ctx)
end

function dispatch:to_handler(fn)
    self.handler = fn
end

function dispatch:find_handler(router)
    local responser = router.responser
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
        local parts = split(strip(router.path .. (router.extra_path or ""), "/"), "/", true)
        local cleaned = {}
        for _, p in ipairs(parts) do
            if p ~= "" then
                cleaned[#cleaned + 1] = p
            end
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
