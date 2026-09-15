local class = require("Tilua.utils.class")

local Controller = class.define()

function Controller:_construct(ctx)
    self.ctx = ctx
end

function Controller:before() end
function Controller:after() end

function Controller:_call(ctx, ...)
    return nil
end

return Controller
