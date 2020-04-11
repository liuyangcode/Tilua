
local ngx = ngx
local var = ngx.var

local class = require('pl.class')
local req = ngx.req
local read_body = req.read_body
local json = require('cjson.safe')

local _request = nil
local routed_uri
---@class request
class.request()

function request:_init()
    self:init_request_args()
end

---初始化输入变量
function request:init_request_args()
    self.get = req.get_uri_args() or {}
    self.method = var.request_method
    if self.method == 'POST' then
        read_body()
        local post = req.get_post_args()
        self.post = json.decode(post) or post or {}
    end
end

function request:get_path_info()
    return var.uri
end
function request:set_routed_uri(uri)
    routed_uri = uri
end
function request:get_routed_uri()
    return routed_uri
end
function request:get_cookie(name)
    return var['cookie_' .. name]
end
---获取GET变量
---@param name string
function request:get(name)
    return self.get[name]
end
---获取POST变量
---@param name string
function request:post(name)
    return self.post[name]
end

function request:set_session(session)
    self.session = session
end

function request:get_header(name)
    local h, err = req.get_headers()
    if err then
        return nil
    end
    return h[name]
end
function request.capture()
    if not _request then
        _request = request()
    end
    return _request
end

return request