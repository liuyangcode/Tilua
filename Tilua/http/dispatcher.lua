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

--- The dispatcher is a container *singleton* (binding "dispatcher"), and it is
--- first built during worker boot — which runs on the Application **class**.
--- Caching that receiver as `self.ctx` meant every request resolved its scoped
--- services (`response`, `request`, `view`, …) on the class container, turning
--- them into shared singletons: request N saw request N-1's response body.
---
--- So `ctx` is read from the live request scope on every entry point instead.
--- `ngx.ctx` is the same slot `Tilua.core.request` parks the request context in.
local function request_ctx()
    if ngx and ngx.ctx then
        local slot = ngx.ctx["__tilua"]
        if slot and slot.ctx then
            return slot.ctx
        end
    end
    return nil
end

function dispatch:_construct(app)
    -- Fallback only: used by tests and non-nginx embedding that never enter a
    -- request scope.  Never relied upon inside a real request.
    self._bootstrap_ctx = app
end

--- The container to resolve services against.  Always the current request
--- context when one exists.
function dispatch:ctx()
    return request_ctx() or self._bootstrap_ctx
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
    local ctx = self:ctx()
    local next_fn = function()
        return self:prepare_response(handler())
    end
    local list = reverse(midware or {})
    return reduce(function(res, next_midware)
        local mid = ctx:make("middleware"):instance(next_midware, ctx)
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

--- Run a middleware chain for a single OpenResty phase.
---
--- Unlike the route chain, a phase chain has no handler: reaching the end means
--- "this phase passed, continue to the next phase", so the terminal returns
--- nil.  A middleware that returns a response short-circuits the request and
--- the caller emits it.
---
--- @param entries table  list of { name, config } from middleware.phase_list()
--- @return table|nil response when a middleware short-circuited
function dispatch:run_phase(entries, ...)
    if type(entries) ~= "table" or #entries == 0 then
        return nil
    end

    local Exception = require("Tilua.core.exception")
    local ctx = self:ctx()
    local chain = reverse(entries)

    local next_fn = function()
        return nil
    end

    for i = 1, #chain do
        local entry = chain[i]
        local prev = next_fn
        next_fn = function(...)
            local mid = ctx:make("middleware"):instance(entry, ctx)
            local func = bind1(mid.handle, mid)
            local ok, out = xpcall(function(...)
                return func(prev, ...)
            end, Exception.handler("middleware"), ...)
            if not ok then
                error(out, 0)
            end
            return out
        end
    end

    local ok, result = xpcall(function(...)
        return next_fn(...)
    end, Exception.handler("middleware"), ...)

    if not ok then
        return nil, result
    end

    -- A middleware may return a bare status / table / string; normalise it
    -- through the same response protocol the route chain uses.
    if result == nil then
        return nil
    end
    if type(result) == "table" and result.send and result.set_body then
        return result
    end
    return self:prepare_response(result)
end

function dispatch:prepare_response(...)
    local res1 = select(1, ...)
    local res2 = select(2, ...)
    local res3 = select(3, ...)
    local res4 = select(4, ...)
    local ctx = self:ctx()
    local response = ctx:make("response")
    local tresponse = type(res1)
    local tcontext = type(res2)
    local as_json = wants_json(ctx)

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
        elseif as_json or (function()
            local req = ctx:make("request")
            return req and type(req.is_json) == "function" and req:is_json()
        end)() then
            local status = (type(res2) == "number" and res2) or (response.status > 0 and response.status) or 200
            response:json(res1, status)
        else
            -- non-API: set as body (may auto-json if response supports table)
            response.body = res1
        end
    elseif tresponse == "string" then
        -- A bare string is plain text, matching the documented route contract
        -- ("return a string to send text").  Passing a table as the second
        -- value explicitly requests a view: `return "index", { title = ... }`.
        --
        -- Historically a bare string was treated as a VIEW NAME, so a route
        -- returning "hello" tried to render the template "hello.html" and the
        -- body came out empty or errored.
        if tcontext == "table" then
            response:render(res1, res2)
        else
            response:text(res1)
        end
    end

    return response
end

--- Collect the positional arguments to pass to a route handler.
---
--- Parameters are bound BY NAME from `router.vals` (the trie/fallback
--- captures).  The previous implementation indexed `vals` by position and
--- skipped any entry whose name contained a digit (`"%d+"` matches anywhere),
--- so `/user/{name}` passed `nil` and `/user/{id2}` was dropped entirely.
local function get_bind_args(router)
    local bind_args = {}
    local vals = router.vals or {}

    for _, name in ipairs(router.args or {}) do
        if type(name) == "string" and not string.match(name, "^%$?%d+$") then
            table.insert(bind_args, vals[name])
        end
    end

    -- A splat / prefix capture is appended as a trailing argument.
    if vals.splat ~= nil and vals.splat ~= "" then
        table.insert(bind_args, vals.splat)
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

--- Build the handler for a matched route.
---
--- The handler MUST stay local.  The dispatcher is a worker-scoped singleton
--- (container binding "dispatcher"), so storing it as `self.handler` leaked the
--- previous request's handler into the next one — every request after the first
--- re-ran the first route's handler.
function dispatch:create_responser(router)
    local midwares = shallow_copy_list(router.midware)
    local handler = router.responser
    local thandler = type(handler)
    local ctx = self:ctx()
    local resolved

    if thandler == "string" then
        resolved = function(...)
            return self:find_handler(router)()
        end
    elseif thandler == "function" then
        local bind_args = get_bind_args(router)
        resolved = function()
            return handler(ctx, table.unpack(bind_args))
        end
    else
        -- Router middleware may install a handler via to_handler(); it lives on
        -- the request context so it cannot leak between requests.
        resolved = rawget(ctx, "_phase_handler")
    end

    if resolved == nil then
        resolved = function()
            return errors.not_found()
        end
    end

    return self:make_chain_call(midwares, resolved)
end

function dispatch:run(matched, router)
    local Exception = require("Tilua.core.exception")
    local ctx = self:ctx()
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
            local as_json = wants_json(ctx)
            return errors.apply(ctx:make("response"), result, as_json ~= false)
        end
        return result
    end
    -- thrown exception
    local ex = Exception.is(result) and result or Exception.wrap(result, "controller")
    Exception.log(ctx, ex)
    return Exception.render(ctx:make("response"), ex, ctx)
end

--- Install a handler for the current request (used by the MVC router
--- middleware).  Stored on the request context, never on the dispatcher
--- singleton, so it cannot leak into the next request.
function dispatch:to_handler(fn)
    rawset(self:ctx(), "_phase_handler", fn)
end

function dispatch:find_handler(router)
    local ctx = self:ctx()
    local responser = router.responser
    if string_find(responser, "@", 1, true) then
        local resp = split(responser, "@", true)
        local controller = resp[1]
        local action = resp[2]
        if not string_find(controller, ctx.name .. ".", 1, true) then
            controller = ctx.name .. "." .. controller
        end
        local handler = lw_util.import(controller)
        local bind_args = get_bind_args(router)
        if handler and type(handler[action]) == "function" then
            return function()
                return handler[action](ctx, table.unpack(bind_args))
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
        local handler = lw_util.import(ctx.name, "controller", controller)
        if handler then
            if handler._construct then
                handler = handler(ctx, controller, action)
            end
            if handler.__parent and not handler.__parent[action] and type(handler[action]) == "function" then
                return function()
                    return handler[action](handler, ctx, table.unpack(params))
                end
            elseif type(handler._call) == "function" then
                return function()
                    return handler._call(handler, ctx, table.unpack(params))
                end
            elseif type(handler[action]) == "function" then
                return function()
                    return handler[action](handler, ctx, table.unpack(params))
                end
            end
        end
    end
    return function()
        return errors.not_found()
    end
end

return dispatch
