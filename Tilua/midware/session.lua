local session = require('Tilua.session')
local session_start = {}
local update = require("pl.tablex").update

---handle
---@param next function
function session_start:handle(next, ...)
    local request, response = self.ctx:unpack()
    local found, save_handler = pcall(require, self.config.save_handler)
    assert(found, 'Cannot find save handler - session startup failed')
    self.config.save_handler = save_handler.new(self.ctx)
    local sess = session(self.config, self.ctx)
    sess:start(request)
    self.ctx.session = sess
    response = next(...)
    response:set_cookie(sess:cookie_to_send())
    sess:close()
    return response
end


local function new (self,ctx,config)
    local default_config = {
        use_strict_mode = true,
        use_cookies = true,
        gc_maxlifetime = 3600,
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

    local instance = {
        ctx = ctx,
        config = update(default_config, config or {})
    }
    return setmetatable(instance,{
        __index = self
    })
end

setmetatable(session_start,{
    __call = new
})


return session_start