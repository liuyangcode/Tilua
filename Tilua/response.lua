local class = require('pl.class')
local tablex = require('pl.tablex')
local ngx = ngx
local send = ngx.say

local ngx_redirect = ngx.redirect
---@class response
local response = class()
---_init
function response:_init(ctx)
    self.ctx = ctx
    self.body = ""
    self.headers = {}
    self.status = 200
    self.after_send_callback = {}
end

function response:after_send(func)
    self.after_send_callback[#self.after_send_callback + 1] = func
end

---发送响应头
function response:send_headers()
    if ngx.headers_sent then
        return
    end
    for k, v in pairs(self.headers) do
        ngx.header[k] = v
    end
    return self
end

function response:render(view, context)
    return self
end

---设置响应头
---@param header table|any
function response:add_header(header, ...)
    local vals = { ... }
    if type(header) == 'string' then
        self.headers[header] = #vals == 1 and vals[1] or vals
    elseif type(header) == 'table' then
        for k, v in pairs(header) do
            self:add_header(k, v)
        end
    end
    return false
end
---add_cookie
---@param name string
---@param value string
---@param path string
---@param expires number
---@param domain string
---@param httponly boolean
---@param secure boolean
function response:set_cookie(name, value, path, expires, domain, httponly, secure)
    local set_cookies = self.headers['Set-Cookie'] or {}
    if type(set_cookies) == 'string' then
        set_cookies = { set_cookies }
    end
    expires = expires or 0
    if not value then
        set_cookies[#set_cookies + 1] = name
    else
        set_cookies[#set_cookies + 1] = string.format(
                '%s=%s;path=%s;expires=%s;%s%s%s',
                name, value,
                path or '/',
                expires > 0 and ngx.cookie_time(ngx.time() + expires) or 0,
                domain and domain .. ';' or '',
                httponly == true and 'httponly;' or '',
                secure == true and 'secure;' or ''
        )
    end
    self.headers['Set-Cookie'] = set_cookies
    return true
end
---发送正文给客户端
function response:send_body()
    if self.status == 200 or self.status == 0 then
        send(self.body)
        tablex.map(function(f)
            f()
        end, self.after_send_callback)
    else
        ngx.exit(self.status)
    end
    return self
end
function response.redirect(...)
    ngx_redirect(...)
end
---发送
function response:send()
    self:send_headers()
    self:send_body()
end
return response