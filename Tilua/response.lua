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

    local tcontent = type(self.body)
    if tcontent == 'string' then
        add_header('Content-Length',#self.body)
    elseif tcontent == 'nil' then
        self.body = ''
        add_header('Content-Length',0)
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
    if self.status == 200 or self.status == 0 then
        send(self.body)
    end
    return ngx.exit(self.status)
end

function response:jump(url, success, message, waitSecond)
    local default_jump_tpl = [[
        <!DOCTYPE html>
        <html>
        <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
            <title>跳转提示</title>
            <style type="text/css">
                *{ padding: 0; margin: 0; }
                body{ background: #fff; font-family: '微软雅黑'; color: #333; font-size: 16px; }
                .system-message{ padding: 24px 48px; }
                .system-message h1{ font-size: 100px; font-weight: normal; line-height: 120px; margin-bottom: 12px; }
                .system-message .jump{ padding-top: 10px}
                .system-message .jump a{ color: #333;}
                .system-message .success,.system-message .error{ line-height: 1.8em; font-size: 36px }
                .system-message .detail{ font-size: 12px; line-height: 20px; margin-top: 12px; display:none}
            </style>
        </head>
        <body>
        <div class="system-message">
            {% if message then %}
            <h1>:)</h1>
            <p class="success">{{message}}</p>
            {% else %}
            <h1>:(</h1>
            <p class="error">{{error}}</p>
            {% end %}
            <p class="detail"></p>
            <p class="jump">
                页面自动 <a id="href" href="{{jumpUrl}}">跳转</a> 等待时间： <b id="wait">{{waitSecond}}</b>
            </p>
        </div>
        <script type="text/javascript">
            (function(){
                var wait = document.getElementById('wait'),href = document.getElementById('href').href;
                var interval = setInterval(function(){
                    var time = --wait.innerHTML;
                    if(time <= 0) {
                        location.href = href;
                        clearInterval(interval);
                    };
                }, 1000);
            })();
        </script>
        </body>
        </html>
    ]]
    local context = {
        jumpUrl = url,
        waitSecond = waitSecond or 3,
        success = not not success
    }
    if success then
        context.message = message
    else
        context.error = message
    end
    self.body = self.ctx.view_engine.template.process(self.ctx.config.jump_tpl or default_jump_tpl, context, nil, not self.ctx.config.jump_tpl)
    return self
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