local class = require("Tilua.utils.class")

local Container = class.define()

function Container:_construct()
    self.bindings = {}
    self.instances = {}
    self.resolving = {}
end

local function assert_name(name)
    assert(type(name) == "string" and name ~= "", "container service name must be a non-empty string")
end

function Container:bind(name, factory, singleton)
    assert_name(name)
    assert(type(factory) == "function", "container binding must be a function")
    self.bindings[name] = {
        factory = factory,
        singleton = singleton == true
    }
    self.instances[name] = nil
    return self
end

function Container:singleton(name, factory)
    return self:bind(name, factory, true)
end

function Container:value(name, value)
    assert_name(name)
    self.bindings[name] = { value = value, singleton = true }
    self.instances[name] = value
    return self
end

function Container:instance(name, value)
    return self:value(name, value)
end

function Container:has(name)
    return self.bindings[name] ~= nil or self.instances[name] ~= nil
end

function Container:get(name)
    assert_name(name)

    if self.instances[name] ~= nil then
        return self.instances[name]
    end

    local binding = self.bindings[name]
    if not binding then
        error("service not found: " .. name, 2)
    end

    if binding.value ~= nil then
        return binding.value
    end

    if self.resolving[name] then
        error("circular dependency while resolving: " .. name, 2)
    end

    self.resolving[name] = true
    local ok, result = xpcall(function()
        return binding.factory(self)
    end, debug.traceback)
    self.resolving[name] = nil

    if not ok then
        error(result, 2)
    end

    if binding.singleton then
        self.instances[name] = result
    end

    return result
end

function Container:make(name, ...)
    assert_name(name)
    local binding = self.bindings[name]
    if not binding then
        error("service not found: " .. name, 2)
    end
    if binding.singleton then
        return self:get(name)
    end
    return binding.factory(self, ...)
end

function Container:remove(name)
    self.bindings[name] = nil
    self.instances[name] = nil
    self.resolving[name] = nil
    return self
end

function Container:clear()
    self.bindings = {}
    self.instances = {}
    self.resolving = {}
    return self
end

function Container:reset(name)
    if name then
        self.instances[name] = nil
    else
        self.instances = {}
    end
    return self
end

function Container:services()
    local result = {}
    for name in pairs(self.bindings) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

return Container
