local class = require "pl.class"
---@class cache
local cache = class()

function cache:_init(ctx)
    self.ctx = ctx
end

function cache.derive()
    return class(cache)
end

return cache

