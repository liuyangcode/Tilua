local class = require('pl.class')


local midware = class()
---_init
---@param app app
function midware:_init(ctx)
    ---@type app
    self.ctx = ctx
end

function midware:hanlde(...)
    assert(false, 'midware is base class ,cannot be instanced')
end

function midware.derive()
    return class(midware)
end

return midware