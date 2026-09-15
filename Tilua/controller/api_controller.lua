local Controller = require("Tilua.controller.controller")

local ApiController = Controller:extend()

function ApiController:success(data, message)
    return {
        code = 0,
        message = message or "ok",
        data = data,
    }
end

function ApiController:error(code, message, data)
    return {
        code = code or 1,
        message = message or "error",
        data = data,
    }
end

return ApiController
