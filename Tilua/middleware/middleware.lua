local class = require("Tilua.utils.class")

local Middleware = class.define()

function Middleware:_construct(options)
    if options then
        for k, v in pairs(options) do
            self[k] = v
        end
    end
end

function Middleware:handle(ctx, next)
    return next()
end

return Middleware
