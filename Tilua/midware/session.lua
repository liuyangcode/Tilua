local session = require('Tilua.session')
local session_start = require('Tilua.midware').derive()
local update = require("pl.tablex").update
local default_config = {
    use_strict_mode = true,
    use_cookies = true,
    gc_maxlifetime = 300,
    gc_divisor = 100,
    name = 'ACCESSTOKEN',
    save_handler = 'Tilua.session.session_redis_hanler',
    serialize_handler = nil,
    use_only_cookies = true,
    referer_check = "",
    lazy_write = 1, --延迟写入
    gc_probability = 1,
    cookie_path = '/',
    cookie_domain = '',
    cookie_expires = 30,
    cookie_http_only = true
}

function session_start:_init(ctx, config)
    self.config = update(default_config,config or {})
    self:super(ctx)
end

---handle
---@param next function
function session_start:handle(next, ...)
    local request, response = self.ctx:unpack()
    session.init_config(self.config)
    session.start(request)
    request.session = session
    ---@type response
    next(...)
    response.set_cookie(session.cookie_to_send())
    session.close()
    return response
end
return session_start