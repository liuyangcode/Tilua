--- Tilua.http.request (v0.2.4)
--- Captures OpenResty request with cached headers, cookie jar,
--- input helpers, AJAX/JSON detection, and safe accessors.

local ngx = ngx
local ngx_req = ngx.req
local ngx_var = ngx.var
local util = require("Tilua.utils.util")
local helpers = require("Tilua.core.helpers")
local cookie_mod = require("Tilua.http.cookie")

local trim = helpers.strip
local imap = helpers.imap
local string_format = string.format
local setmetatable, rawget, rawset = setmetatable, rawget, rawset
local type = type
local lower = string.lower

---@class request
local request = {}

-------------------------------------------------
-- ngx.var based getters (no allocation)
-------------------------------------------------

function request.get_host()
    return ngx_var.host
end

function request.get_query_string()
    return ngx_var.query_string
end

function request.get_query()
    return ngx_req.get_uri_args()
end

function request.get_args()
    return ngx_req.get_uri_args()
end

function request.get_remote_addr()
    return ngx_var.remote_addr
end

function request.get_remote_port()
    return ngx_var.remote_port
end

function request.get_raw_request()
    return ngx_var.request
end

function request.get_filename()
    return ngx_var.request_filename
end

function request.get_document_root()
    return ngx_var.document_root
end

function request.get_scheme()
    return ngx_var.scheme
end

function request.get_method()
    return ngx_var.request_method
end

function request.get_uri()
    return ngx_var.request_uri
end

function request.get_path_info()
    return ngx_var.uri
end

function request.get_hostname()
    return ngx_var.hostname
end

function request.get_server_name()
    return ngx_var.server_name
end

function request.get_server_port()
    return ngx_var.server_port
end

function request.get_server_protocol()
    return ngx_var.server_protocol
end

function request.get_server_version()
    return ngx_var.nginx_version
end

function request.get_pid()
    -- ngx.var.pid is a string variable, not a function
    local ok, pid = pcall(function()
        return ngx.worker.pid()
    end)
    if ok then
        return pid
    end
    return ngx_var.pid
end

-------------------------------------------------
-- UA (lazy: only load parser when accessed)
-------------------------------------------------

local function ua_header()
    return ngx_req.get_headers()["user-agent"] or ngx_req.get_headers()["User-Agent"]
end

function request.get_platform()
    local useragent = require("Tilua.utils.useragent")
    return useragent.parse_platform(ua_header())
end

function request.get_browser()
    local useragent = require("Tilua.utils.useragent")
    return useragent.parse_browser(ua_header())
end

function request.get_mobile()
    local useragent = require("Tilua.utils.useragent")
    return useragent.parse_mobile(ua_header())
end

function request.get_robot()
    local useragent = require("Tilua.utils.useragent")
    return useragent.parse_robot(ua_header())
end

function request.get_wechat()
    local useragent = require("Tilua.utils.useragent")
    return useragent.parse_wechat(ua_header())
end

-------------------------------------------------
-- body
-------------------------------------------------

function request.set_body(self, value)
    if value == nil then
        self._body = {}
        return
    end
    if type(value) ~= "table" then
        return
    end
    for k, val in pairs(value) do
        if type(val) == "table" then
            self._body[k] = imap(trim, val)
        elseif type(val) == "string" then
            self._body[k] = trim(val)
        else
            self._body[k] = val
        end
    end
end

function request.get_body(self)
    return self._body
end

-------------------------------------------------
-- headers
-------------------------------------------------

--- Headers.
---
--- NOTE: capture() may run during rewrite_by_lua, where OpenResty's
--- `ngx.req.get_headers()` does not yet expose every request header — a
--- snapshot taken there can miss custom headers entirely (measured: a client
--- sent `X-Admin-Token` and `ngx.var.http_x_admin_token` was set, while the
--- captured table held only `connection` and `host`).
---
--- So headers are read live on access.
---
--- API caveat: the class system's `__index` wrapper calls any `get_*` method as
--- `method(request)`, discarding arguments.  Therefore `req:get_header("X")`
--- would receive the request table as `name`.  Use the `header` table directly
--- (`req.header["x-name"]`), or call `req.get_header("X")` without the colon.
function request.get_header(name)
    local headers = ngx_req.get_headers()
    if not name or type(name) ~= "string" then
        return headers
    end
    return headers[name] or headers[name:lower()]
end

request.get_headers = request.get_header

-------------------------------------------------
-- high-level helpers (instance methods via capture)
-------------------------------------------------

function request.is_get(self)
    return lower(self.method or "") == "get"
end

function request.is_post(self)
    return lower(self.method or "") == "post"
end

function request.is_put(self)
    return lower(self.method or "") == "put"
end

function request.is_delete(self)
    return lower(self.method or "") == "delete"
end

function request.is_ajax(self)
    local xrw = self.header["x-requested-with"] or self.header["X-Requested-With"]
    return xrw and lower(tostring(xrw)) == "xmlhttprequest"
end

function request.is_json(self)
    local ct = self.header["content-type"] or self.header["Content-Type"] or ""
    return lower(tostring(ct)):find("json", 1, true) ~= nil
end

function request.wants_json(self)
    if self:is_ajax() then
        return true
    end
    local accept = self.header["accept"] or self.header["Accept"] or ""
    accept = lower(tostring(accept))
    if accept:find("application/json", 1, true) then
        return true
    end
    return self:is_json()
end

--- Client IP (optional X-Forwarded-For first hop when trusted_proxy)
function request.client_ip(self)
    local cfg = self.ctx and self.ctx.config
    if cfg and cfg.trust_proxy then
        local xff = self.header["x-forwarded-for"] or self.header["X-Forwarded-For"]
        if xff and xff ~= "" then
            local first = tostring(xff):match("^([^,]+)")
            if first then
                return trim(first)
            end
        end
        local real = self.header["x-real-ip"] or self.header["X-Real-IP"]
        if real and real ~= "" then
            return tostring(real)
        end
    end
    return self.remote_addr
end

--- Merge query + body (body wins on key conflict)
function request.input(self, key, default)
    local q = self.query or {}
    local b = self._body or {}
    if key == nil then
        local merged = {}
        for k, v in pairs(q) do
            merged[k] = v
        end
        for k, v in pairs(b) do
            merged[k] = v
        end
        return merged
    end
    if b[key] ~= nil then
        return b[key]
    end
    if q[key] ~= nil then
        return q[key]
    end
    return default
end

function request.bearer_token(self)
    local auth = self.header["authorization"] or self.header["Authorization"]
    if not auth then
        return nil
    end
    local token = tostring(auth):match("^[Bb]earer%s+(.+)$")
    return token and trim(token) or nil
end

-------------------------------------------------
-- capture
-------------------------------------------------

function request.capture(ctx)
    local headers = ngx_req.get_headers()
    local raw_cookie = ngx_var.http_cookie or ""
    local jar = cookie_mod.parse(raw_cookie)

    local req = {
        _body = {},
        header = headers,
        params = {},
        ctx = ctx,
        routed_uri = "",
        cookie = setmetatable(jar, {
            __index = function(t, name)
                local v = rawget(t, name)
                if v ~= nil then
                    return v
                end
                local nv = ngx.var["cookie_" .. name]
                if nv then
                    rawset(t, name, nv)
                end
                return nv
            end,
        }),
    }

    local new_request = setmetatable(req, {
        __index = function(t, key)
            -- instance methods that need self
            local method = rawget(request, key)
            if type(method) == "function" then
                -- methods defined as request.foo(self) for helpers
                if key == "is_get" or key == "is_post" or key == "is_put" or key == "is_delete"
                    or key == "is_ajax" or key == "is_json" or key == "wants_json"
                    or key == "client_ip" or key == "input" or key == "bearer_token"
                    or key == "set_body" or key == "get_body" then
                    return function(_, ...)
                        return method(t, ...)
                    end
                end
            end

            local getter = rawget(request, "get_" .. key)
            if util.callable(getter) then
                return getter(t)
            elseif request[key] then
                return request[key]
            else
                return ngx_var[key]
            end
        end,
        __newindex = function(t, name, value)
            local setter = request["set_" .. name]
            if util.callable(setter) then
                return setter(t, value)
            end
            rawset(t, name, value)
        end,
    })

    if ctx.logger and ctx.logger.write then
        local ok, err = pcall(function()
            ctx.logger:write(string_format(
                "\n[%s] %s %s",
                ngx.localtime(),
                new_request.remote_addr or "-",
                new_request.raw_request or "-"
            ))
        end)
        if not ok and ctx.logger.error then
            ctx.logger:error("request log failed: ", tostring(err))
        end
    end

    return new_request
end

return request
