local json_response = require('Tilua.midware').derive()
local json_encode = require("Tilua.util").json_encode
local lw_util = require('Tilua.util')

function json_response:_init(...)
    self:super(...)
end

function json_response:handle(next, ...)
    local _, response = self.ctx:unpack()
    next(...)
    if type(response.body) == 'table' then
        response:add_header('content_type', "application/json;chartset=uft-8")
        response.body = json_encode(response.body) or response.body
    end
end

return json_response