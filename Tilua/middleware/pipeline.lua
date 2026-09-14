local Pipeline = {}
Pipeline.__index = Pipeline

function Pipeline.new(middlewares)
    return setmetatable({ middlewares = middlewares or {} }, Pipeline)
end

function Pipeline:use(middleware)
    self.middlewares[#self.middlewares + 1] = middleware
    return self
end

function Pipeline:handle(ctx, terminal)
    local list = self.middlewares
    local index = 0
    local function next_handler()
        index = index + 1
        local middleware = list[index]
        if middleware == nil then
            if terminal then return terminal(ctx) end
            return nil
        end
        local handler = middleware.handle
        assert(type(handler) == "function", "middleware must provide handle(ctx, next)")
        return handler(middleware, ctx, next_handler)
    end
    return next_handler()
end

function Pipeline:run(ctx, terminal)
    return self:handle(ctx, terminal)
end

return Pipeline
