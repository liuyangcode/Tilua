

local session = require('Tilua.session')
local session_start = require('Tilua.midware').derive()
function session_start:_init(...)

    self:super(...)
end

---handle
---@param next function
---@param request request
function session_start:handle(next, request, ...)
    session.start(request, self.app:get_config('session'))
    request:set_session(session)
    ---@type response
    local response = next(request, ...)
    response:set_cookie(session.cookie_to_send())
    session.close()
    return response
end
return session_start