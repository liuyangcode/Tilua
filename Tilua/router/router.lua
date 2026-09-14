local Route = require("Tilua.router.route")
local Compiler = require("Tilua.router.compiler")
local Matcher = require("Tilua.router.matcher")
local Trie = require("Tilua.router.trie")

local Router = {}
Router.__index = Router

local function normalize_methods(methods)
    if type(methods) == "string" then
        local result = {}
        for method in methods:gmatch("[^,%s]+") do result[#result + 1] = string.upper(method) end
        return result
    end
    if type(methods) == "table" then
        local result = {}
        for _, method in ipairs(methods) do result[#result + 1] = string.upper(method) end
        return result
    end
    return { "*" }
end

local function normalize_path(path)
    if not path or path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    if #path > 1 then path = path:gsub("/+", "/") end
    return path
end

function Router.new(definitions)
    local self = setmetatable({
        _routes = {},
        _names = {},
        _compiled = false,
        _trie = Trie()
    }, Router)

    if type(definitions) == "table" then
        if #definitions > 0 then
            for _, definition in ipairs(definitions) do self:add_definition(definition) end
        else
            for path, handler in pairs(definitions) do
                if type(handler) == "table" and (handler.handler or handler.res or handler.responser) then
                    local methods = handler.methods or handler.method or "*"
                    self:add(methods, path, handler.handler or handler.responser or handler.res, handler.middleware or handler.midware, handler)
                elseif type(handler) == "string" or type(handler) == "function" then
                    self:add("*", path, handler)
                end
            end
        end
    end
    return self
end

function Router:add_definition(definition)
    if type(definition) ~= "table" then return nil, "route definition must be a table" end
    return self:add(
        definition.methods or definition.method or "*",
        definition.path,
        definition.handler or definition.responser or definition.res,
        definition.middleware or definition.midware or definition.mid,
        definition
    )
end

function Router:add(methods, path, handler, middleware, options)
    if type(methods) == "table" and methods.methods == nil and path == nil then
        return self:add_definition(methods)
    end
    if not path then return nil, "route path is required" end
    if not handler then return nil, "route handler is required" end

    options = options or {}
    local route = Route({
        name = options.name,
        path = normalize_path(path),
        handler = handler,
        methods = normalize_methods(methods),
        middleware = middleware,
        meta = options.meta or {}
    })
    if self._names[route.name] then return nil, "duplicate route name: " .. tostring(route.name) end
    self._routes[#self._routes + 1] = route
    if route.name then self._names[route.name] = route end
    self._compiled = false
    return route
end

for _, method in ipairs({ "get", "post", "put", "patch", "delete", "options" }) do
    Router[method] = function(self, path, handler, middleware, options)
        return self:add(method:upper(), path, handler, middleware, options)
    end
end

function Router:any(path, handler, middleware, options)
    return self:add("*", path, handler, middleware, options)
end

function Router:compile()
    if self._compiled then return self end
    self._trie:clear()
    for _, route in ipairs(self._routes) do
        Compiler.route(route)
        self._trie:add(route)
    end
    self._compiled = true
    return self
end

function Router:match(method, path)
    self:compile()
    method = string.upper(method or "GET")
    path = normalize_path(path)

    local candidates = self._trie:find(path)
    local method_allowed = false
    for _, route in ipairs(candidates) do
        if Matcher.path(route, path) then
            if route:allows(method) then
                return Matcher.match(route, method, path)
            end
            method_allowed = true
        end
    end

    if method_allowed then return nil, "method_not_allowed" end
    return nil, "not_found"
end

function Router:dispatch(ctx)
    local request = ctx.request
    local method = request and request:method() or (ngx and ngx.req and ngx.req.get_method())
    local path = request and request:path() or (ngx and ngx.var and ngx.var.uri) or "/"
    local result, err = self:match(method, path)
    if not result then return nil, err end
    if ctx.set_route then ctx:set_route(result) else ctx.route, ctx.params = result.route, result.params end
    return result.route.handler, result
end

Router.run = Router.dispatch

function Router:routes()
    local result = {}
    for i, route in ipairs(self._routes) do result[i] = route end
    return result
end

function Router:find(name)
    return self._names[name]
end

return setmetatable(Router, {
    __call = function(_, definitions) return Router.new(definitions) end
})
