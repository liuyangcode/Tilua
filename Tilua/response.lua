local ngx = ngx
local send = ngx.print
local lw_util = require('Tilua.util')

local ngx_redirect = ngx.redirect
local setmetatable = setmetatable
local add_header = require("ngx.resp").add_header
local lower = string.lower
local format = string.format
local rawget, type = rawget, type
---@class response
local response = {}
---_init
function response.init_context(context)
    ctx = context
    return setmetatable(response, {
        __index = function(_, prop)
            prop = lower(prop)
            local getter = 'get_' .. prop
            if rawget(response, getter) and lw_util.callable(response[getter]) then
                return response[getter]()
            end
            return nil
        end,
        __newindex = function(_, prop, value)
            prop = lower(prop)
            local setter = 'set_' .. prop
            if rawget(response, setter) and lw_util.callable(response[setter]) then
                return response[setter](value)
            end
            return nil
        end
    })
end

function response:get_body()
    return self.body
end

function response:set_body(content)
    local tcontent = type(content)
    if tcontent == 'string' then
        self.headers.content_length = #content
    elseif tcontent == 'nil' then
        self.body = ''
        self.headers.content_length = 0
    end
    self.body = content
end

---发送响应头
function response:send_headers()
    if ngx.headers_sent then
        return
    end
    local has_content_type
    for k, v in pairs(self.headers) do
        local tvalue = type(v)
        if tvalue == "string" then
            v = (v == "" and " " or v)
            v = tostring(v)
        elseif tvalue == 'table' then
            local new_value = {}
            for i, val in ipairs(v) do
                new_value[i] = val == "" and " " or val
            end
            v = new_value
        end
        if not has_content_type then
            local lower_name = lower(k)
            if lower_name == "content-type" or
                    lower_name == "content_type" then
                has_content_type = true
            end
        end
        add_header(k, v)
    end
    if not has_content_type then
        add_header('content-type', self.ctx.config.default_content_type .. '; charset=' .. self.ctx.config.default_charset)
    end
    return self
end

function response:render(view, context, content_type)
    if content_type then
        self.headers.content_type = content_type
    end
    self.body = self.ctx.view:render(view, context)
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

function response:attachment()

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
    if not name then
        set_cookies = {}
    else
        if type(set_cookies) == 'string' then
            set_cookies = { set_cookies }
        end
        expires = expires or 0
        if not value then
            local tname = type(name)
            if tname == 'string' then
                set_cookies[#set_cookies + 1] = name
            elseif tname == 'table' then
                set_cookies[#set_cookies + 1] = format(
                        '%s=%s;path=%s;expires=%s;%s%s%s',
                        name.name,
                        name.value,
                        name.path or '/',
                        name.expires and name.expires > 0 and ngx.cookie_time(ngx.time() + name.expires) or 0,
                        name.domain and name.domain .. ';' or '',
                        name.httponly == true and 'httponly;' or '',
                        name.secure == true and 'secure;' or ''
                )
            end
        else
            set_cookies[#set_cookies + 1] = format(
                    '%s=%s;path=%s;expires=%s;%s%s%s',
                    name,
                    value,
                    path or '/',
                    expires > 0 and ngx.cookie_time(ngx.time() + expires) or 0,
                    domain and domain .. ';' or '',
                    httponly == true and 'httponly;' or '',
                    secure == true and 'secure;' or ''
            )
        end
    end
    self.headers['Set-Cookie'] = set_cookies
    return true
end
---发送正文给客户端
function response:send_body()
    ngx.status = self.status
    if self.status == 200 or self.status == 0 then
        send(self.body)
    end
    return ngx.exit(self.status)
end

response.redirect = ngx_redirect

function response.new(ctx)
    return setmetatable({
        ctx = ctx,
        headers = {},
        status = 0,
        body = nil,
    }, {
        __index = response
    })
end

---发送
function response:send()
    self:send_headers()
    self:send_body()
end

return response