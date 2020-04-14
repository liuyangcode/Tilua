local class = require "pl.class"
local lw_util = require('Tilua.util')
---@class cache
class.cache()
---私有变量
local instances = {}
local context = nil

function cache:_init(ctx)
    self.app = ctx
end
function cache.init(ctx)
    context = ctx
end

function cache.instance(config)
    if type(config) == 'string' then
        config = { type = config }
    end
    assert(config.type, "cache type cannot be nil")
    local hash = lw_util.get_hash(config)
    if instances and instances[hash] then
        return instances[hash]
    end
    instances = instances or {}
    local ok, driver = pcall(require, "Tilua.cache.driver." .. config.type)
    assert(ok, 'unsupported cache type ' .. config.type)
    instances[hash] = driver(config,context )
    return instances[hash]
end

function cache.get(key)

end

function cache.derive()
    return class(cache)
end

return cache

