local Registry = {}
Registry.__index = Registry

function Registry.new()
    return setmetatable({ definitions = {}, aliases = {} }, Registry)
end

function Registry:register(name, middleware, options)
    assert(type(name) == "string" and name ~= "", "middleware name is required")
    assert(middleware ~= nil, "middleware is required")
    self.definitions[name] = { middleware = middleware, options = options or {} }
    return self
end

function Registry:alias(name, target)
    self.aliases[name] = target
    return self
end

function Registry:resolve(name)
    local target = self.aliases[name] or name
    local definition = self.definitions[target]
    if not definition then
        return nil, "middleware not found: " .. tostring(name)
    end
    return definition.middleware, definition.options
end

function Registry:has(name)
    return self:resolve(name) ~= nil
end

function Registry:all()
    return self.definitions
end

return Registry
