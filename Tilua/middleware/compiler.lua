local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(registry)
    return setmetatable({ registry = registry }, Compiler)
end

local function instantiate(definition, options, ctx)
    if type(definition) == "function" then
        local ok, instance = pcall(definition, options, ctx)
        if ok then return instance end
        return definition
    end
    if type(definition) == "table" then
        if type(definition.new) == "function" then
            return definition.new(definition, options, ctx)
        end
        if type(definition._construct) == "function" then
            local instance = setmetatable({}, { __index = definition })
            definition._construct(instance, options, ctx)
            return instance
        end
    end
    return definition
end

function Compiler:compile(spec)
    if spec == nil then return {} end
    if type(spec) ~= "table" then spec = { spec } end
    local compiled = {}
    for i = 1, #spec do
        local item = spec[i]
        if type(item) == "string" then
            local definition, options = self.registry:resolve(item)
            assert(definition, "middleware not found: " .. item)
            compiled[#compiled + 1] = { name = item, definition = definition, options = options }
        elseif type(item) == "function" or type(item) == "table" then
            compiled[#compiled + 1] = { definition = item, options = {} }
        else
            error("invalid middleware definition at index " .. i)
        end
    end
    return compiled
end

function Compiler:instantiate(compiled, ctx)
    local result = {}
    for i = 1, #compiled do
        local item = compiled[i]
        result[i] = instantiate(item.definition, item.options, ctx)
    end
    return result
end

return Compiler
