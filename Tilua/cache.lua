local class = require "pl.class"
---@class cache
local cache = class()

function cache:_init(config, context, logger)
    self.config = config
    self.ctx = context
    self.logger = logger
end

function cache:close()
    --todo
    --close action
end

function cache.derive()
    return class(cache)
end

return cache

