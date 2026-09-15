--- Tilua.http.response (v0.2.4)
--- Chainable helpers: json/text/html, status, cookies, attachment, send

local ngx = ngx
local send = ngx.print
local class = require("Tilua.utils.class")
local cookie = require("Tilua.http.cookie")
local add_header = require("ngx.resp").add_header

local lower = string.lower
local type = type
local pairs = pairs
local ipairs = ipairs

---@class response
local response = class.define()

-------------------------------------------------
-- body
-------------------------------------------------

function response:get_body()
    return self._body
end

function response:set_body(content)
    local t = type(content)
    if t == "nil" then
        self._body = ""
        self.headers["Content-Length"] = 0
    elseif t == "string" then
        self._body = content
        self.headers["Content-Length"] = #content
    elseif t == "table" then
        -- encode as JSON if no content-type forced yet
        local cjson = require("cjson.safe")
        local encoded = cjson.encode(content) or "null"
        self._body = encoded
        self.headers["Content-Length"] = #encoded
        if not self:_has_content_type() then
            self.headers["Content-Type"] = "application/json; charset=utf-8"
        end
    else
        self._body = tostring(content)
        self.headers["Content-Length"] = #self._body
    end
    return self
end

-- property-style access used by dispatcher (response.body = ...)
function response:__newindex_body(key, value)
    if key == "body" then
        return self:set_body(value)
    end
end

-------------------------------------------------
-- headers
-------------------------------------------------

function response:_has_content_type()
    for k in pairs(self.headers) do
        local lk = lower(k)
        if lk == "content-type" or lk == "content_type" then
            return true
        end
    end
    return false
end

function response:set_header(name, value)
    if name == nil then
        return self
    end
    self.headers[name] = value
    return self
end

--- add_header(name, value) or add_header({k=v, ...})
function response:add_header(header, ...)
    if type(header) == "string" then
        local vals = { ... }
        if #vals == 0 then
            return self
        end
        self.headers[header] = #vals == 1 and vals[1] or vals
    elseif type(header) == "table" then
        for k, v in pairs(header) do
            self.headers[k] = v
        end
    end
    return self
end

function response:content_type(ct)
    if ct then
        self.headers["Content-Type"] = ct
    end
    return self
end

function response:set_status(code)
    code = tonumber(code) or 0
    rawset(self, "status", code)
    if code > 0 then
        ngx.status = code
    end
    return self
end

function response:get_status()
    return rawget(self, "status") or 0
end

function response:status_code(code)
    if code then
        return self:set_status(code)
    end
    return self:get_status()
end

response.code = response.status_code


-------------------------------------------------
-- content helpers
-------------------------------------------------

function response:json(data, status)
    if status then
        self:status_code(status)
    end
    self.headers["Content-Type"] = "application/json; charset=utf-8"
    local cjson = require("cjson.safe")
    local body = cjson.encode(data)
    if body == nil then
        body = "null"
    end
    return self:set_body(body)
end

function response:text(str, status)
    if status then
        self:status_code(status)
    end
    self.headers["Content-Type"] = "text/plain; charset=utf-8"
    return self:set_body(str or "")
end

function response:html(str, status)
    if status then
        self:status_code(status)
    end
    self.headers["Content-Type"] = "text/html; charset=utf-8"
    return self:set_body(str or "")
end

function response:no_content()
    self:status_code(204)
    self._body = ""
    self.headers["Content-Length"] = 0
    return self
end

function response:render(view, context, content_type)
    if content_type then
        self.headers["Content-Type"] = content_type
    end
    if self.ctx and self.ctx.view and self.ctx.view.render then
        self:set_body(self.ctx.view:render(view, context))
    else
        self:set_body("")
    end
    return self
end

--- File download header
function response:attachment(filename, content_type)
    filename = filename or "download"
    -- strip path separators
    filename = filename:gsub("[/\\]", "_")
    self.headers["Content-Disposition"] = 'attachment; filename="' .. filename .. '"'
    if content_type then
        self.headers["Content-Type"] = content_type
    end
    return self
end

function response:inline(filename, content_type)
    filename = (filename or "file"):gsub("[/\\]", "_")
    self.headers["Content-Disposition"] = 'inline; filename="' .. filename .. '"'
    if content_type then
        self.headers["Content-Type"] = content_type
    end
    return self
end

-------------------------------------------------
-- cookies
-------------------------------------------------

local function cookie_list(headers)
    local cur = headers["Set-Cookie"] or headers["set-cookie"]
    if not cur then
        return {}
    end
    if type(cur) == "string" then
        return { cur }
    end
    return cur
end

function response:set_cookie(name, value, path, expires, domain, httponly, secure, samesite)
    local list = cookie_list(self.headers)
    local line

    if name == nil then
        self.headers["Set-Cookie"] = {}
        return self
    end

    if type(name) == "string" and value == nil then
        line = name
    elseif type(name) == "table" then
        line = cookie.build(name)
    else
        line = cookie.build({
            name = name,
            value = value,
            path = path or "/",
            expires_in = expires,
            max_age = expires,
            domain = domain,
            httponly = httponly == nil and true or httponly,
            secure = secure,
            samesite = samesite or "Lax",
        })
    end

    if line and line ~= "" then
        list[#list + 1] = line
    end
    self.headers["Set-Cookie"] = list
    return self
end

function response:clear_cookie(name, opts)
    opts = opts or {}
    local list = cookie_list(self.headers)
    list[#list + 1] = cookie.build_clear(name, opts)
    self.headers["Set-Cookie"] = list
    return self
end

response.delete_cookie = response.clear_cookie

-------------------------------------------------
-- send
-------------------------------------------------

function response:send_headers(without_body)
    if ngx.headers_sent then
        return self
    end

    if self.status and self.status > 0 then
        ngx.status = self.status
    end

    local has_content_type = false
    for k, v in pairs(self.headers) do
        local tvalue = type(v)
        if tvalue == "string" then
            v = (v == "" and " " or v)
        elseif tvalue == "table" then
            local new_value = {}
            for i, val in ipairs(v) do
                new_value[i] = val == "" and " " or val
            end
            v = new_value
        elseif tvalue == "number" then
            v = tostring(v)
        end

        local lower_name = lower(k)
        if lower_name == "content-type" or lower_name == "content_type" then
            has_content_type = true
            -- normalize key
            k = "Content-Type"
        elseif lower_name == "content-length" or lower_name == "content_length" then
            k = "Content-Length"
        end

        add_header(k, v)
    end

    if without_body then
        return self
    end

    if not has_content_type and self.ctx and self.ctx.config then
        local ct = self.ctx.config.default_content_type or "text/html"
        local cs = self.ctx.config.default_charset or "utf-8"
        add_header("Content-Type", ct .. "; charset=" .. cs)
    end

    return self
end

function response:send_body()
    local status = self.status or 0
    if status == 0 then
        status = 200
        self.status = 200
        ngx.status = 200
    end

    -- 204/304 must not have body
    if status == 204 or status == 304 then
        return ngx.exit(status)
    end

    local body = self._body
    if body == nil then
        body = ""
    end

    -- always try to print body for statuses that allow it
    if type(body) == "string" and #body > 0 then
        send(body)
    elseif type(body) == "string" then
        -- empty ok
    else
        send(tostring(body))
    end

    return ngx.exit(status)
end

function response:send()
    self:send_headers()
    return self:send_body()
end

function response:headers_sent()
    return ngx.headers_sent and true or false
end

-------------------------------------------------
-- redirect / jump
-------------------------------------------------

function response:redirect(url, status)
    status = status or 302
    self:status_code(status)
    self.headers["Location"] = url
    self._body = ""
    self.headers["Content-Length"] = 0
    return self
end

-- keep ngx.redirect as low-level escape hatch
response.ngx_redirect = ngx.redirect

function response:jump(url, success, message, waitSecond)
    local default_jump_tpl = [=[
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>跳转提示</title>
<style type="text/css">
*{padding:0;margin:0}
body{background:#fff;font-family:sans-serif;color:#333;font-size:16px}
.system-message{padding:24px 48px}
.system-message h1{font-size:72px;font-weight:normal;line-height:1.2;margin-bottom:12px}
.system-message .jump{padding-top:10px}
.system-message .success,.system-message .error{line-height:1.8;font-size:28px}
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
<p class="jump">页面自动 <a id="href" href="{{jumpUrl}}">跳转</a> 等待：<b id="wait">{{waitSecond}}</b></p>
</div>
<script>
(function(){
  var wait=document.getElementById('wait'),href=document.getElementById('href').href;
  var interval=setInterval(function(){
    var time=--wait.innerHTML;
    if(time<=0){location.href=href;clearInterval(interval)}
  },1000);
})();
</script>
</body>
</html>
]=]

    local context = {
        jumpUrl = url,
        waitSecond = waitSecond or 3,
        success = not not success,
    }
    if success then
        context.message = message
    else
        context.error = message
    end

    local tpl = (self.ctx and self.ctx.config and self.ctx.config.jump_tpl) or default_jump_tpl
    if self.ctx and self.ctx.view_engine and self.ctx.view_engine.template then
        self:set_body(self.ctx.view_engine.template.process(tpl, context, nil, not (self.ctx.config and self.ctx.config.jump_tpl)))
    else
        self:html(message or "", success and 200 or 400)
    end
    return self
end

-------------------------------------------------
-- construct + body property bridge
-------------------------------------------------

function response:_construct(ctx)
    self.ctx = ctx
    self.headers = {}
    rawset(self, "status", 0)
    self._body = nil
end

return response

