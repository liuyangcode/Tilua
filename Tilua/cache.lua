local class = require "pl.class"
local lw_util = require('Tilua.util')
---@class cache
local cache = class()
---私有变量
local instances = {}
local context = nil

function cache:_init(ctx)
    self.ctx = ctx
end

function cache.init(ctx)
    context = ctx
    cache.catch(cache.magic)
    return cache
end
function cache.magic(ctx, name)
    if context.config[name] then
        return cache.instance(context.config[name])
    else
        return cache.instance(name)
    end
end
function cache.instance(config)
    if type(config) == 'string' then
        config = { type = config }
    end
    --assert(config.type, "cache type cannot be nil")
    local hash = lw_util.get_hash(config)
    if instances and instances[hash] then
        return instances[hash]
    end
    instances = instances or {}
    local ok, driver = pcall(require, "Tilua.cache.driver." .. config.type)
    assert(ok, 'unsupported cache type ' .. config.type)
    instances[hash] = driver(config, context)
    return instances[hash]
end

---get
---@param key string
function cache.get(key)
    return cache.instance(context.config.data_cache_type):get(context.config.data_cache_prefix .. key)
end
---set
---@param name string
---@param value any
---@param expire number
function cache.set(name, value, expire)
    return cache.instance(context.config.data_cache_type):set(context.config.data_cache_prefix .. name, value, expire)
end

---del
---@param name string
function cache.del(name)
    return cache.instance(context.config.data_cache_type):del(context.config.data_cache_prefix .. name)
end

function cache.derive()
    return class(cache)
end

return cache

