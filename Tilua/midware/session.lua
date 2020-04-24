local session = require('Tilua.session')
local session_start = require('Tilua.midware').derive()
function session_start:_init(...)
    self:super(...)
end

---handle
---@param next function
function session_start:handle(next, ...)
    local request, response, _, config = self.ctx:unpack()
    session.start(request, config.session)
    request.session = session
    ---@type response
    next(...)
    response:set_cookie(session.cookie_to_send())
    session.close()
    return response
end
return session_start