local util = require("Tilua.utils.util")

local Invoker = {}
Invoker.__index = Invoker

local function split_action(target)
    local p = target:find("@", 1, true)
    if not p then return target, nil end
    return target:sub(1, p - 1), target:sub(p + 1)
end

local function invoke_function(fn, ctx, params)
    return fn(ctx, table.unpack(params or {}))
end

function Invoker.new(app)
    return setmetatable({ app = app }, Invoker)
end

function Invoker:resolve(handler, ctx, params)
    if type(handler) == "function" then
        return function()
            return invoke_function(handler, ctx, params)
        end
    end

    if type(handler) ~= "string" then
        return nil, "invalid_handler"
    end

    local controller_name, action = split_action(handler)
    if not action then
        return nil, "invalid_handler"
    end

    local controller = util.import(controller_name)
    if not controller then
        controller = util.import(ctx.name, "controller", controller_name)
    end
    if not controller then
        return nil, "controller_not_found"
    end

    local fn = controller[action]
    if type(fn) ~= "function" then
        return nil, "action_not_found"
    end

    return function()
        return fn(controller, ctx, table.unpack(params or {}))
    end
end

function Invoker:invoke(handler, ctx, params)
    local fn, err = self:resolve(handler, ctx, params)
    if not fn then
        return nil, err
    end
    return fn()
end

return Invoker
