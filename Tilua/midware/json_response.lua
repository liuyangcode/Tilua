local json_response = {}
local json_encode = require("Tilua.utils.util").json_encode

function json_response:handle(next, ...)
    local response = next(...)
    if type(response.body) == 'table' then
        response:add_header('content_type', "application/json;chartset=uft-8")
        response.body = json_encode(response.body) or response.body
    end
    return response
end

local  function new (self,ctx)
    local instance = {
        ctx = ctx
    }
    return setmetatable(instance,{
        __index = self
    })
end

setmetatable(json_response,{
    __call = new
})

return json_response