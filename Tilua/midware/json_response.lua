local base = require("Tilua.midware.base")
local json_response = base.define()

local json_encode = require("Tilua.utils.util").json_encode

function json_response:handle(next, ...)
    local response = next(...)
    if type(response.body) == 'table' then
        response:add_header('content_type', "application/json;chartset=uft-8")
        response.body = json_encode(response.body) or response.body
    end
    return response
end

return json_response