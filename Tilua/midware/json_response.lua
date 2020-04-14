local json_response = require('Tilua.midware').derive()
local json_encode = require("Tilua.util").json_encode
function json_response:_init(...)
    self:super(...)
end

function json_response:handle(next, request, ...)
    local response = next(request, ...)
    response:add_header('content_type', "application/json;chartset=uft-8")
    if type(response.body) == 'table' then
        response.body = json_encode(response.body) or response.body
    end
    return response
end

return json_response