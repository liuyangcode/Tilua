local Route = {}
Route.__index = Route

local function copy_array(value)
    local result = {}
    if type(value) == "table" then
        for i, item in ipairs(value) do
            result[i] = item
        end
    end
    return result
end

function Route.new(definition)
    definition = definition or {}
    local self = setmetatable({}, Route)
    self.name = definition.name
    self.path = definition.path or "/"
    self.handler = definition.handler or definition.responser or definition.res
    self.methods = copy_array(definition.methods or definition.method)
    if #self.methods == 0 then self.methods = { "*" } end
    self.middleware = copy_array(definition.middleware or definition.midware or definition.mid)
    self.meta = definition.meta or {}
    self.compiled = definition.compiled
    self.matcher = definition.matcher
    self.params = copy_array(definition.params)
    return self
end

function Route:allows(method)
    method = string.upper(method or "GET")
    for _, allowed in ipairs(self.methods) do
        if allowed == "*" or string.upper(allowed) == method then return true end
    end
    return false
end

function Route:clone()
    return Route.new(self)
end

return setmetatable(Route, {
    __call = function(_, definition) return Route.new(definition) end
})
