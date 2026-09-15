local ngx = ngx
local ngx_req = ngx.req
local ngx_var = ngx.var
local util = require("Tilua.utils.util")
local useragent = require("Tilua.utils.useragent")

local trim = require("pl.stringx").strip
local tablex = require("pl.tablex")
local string_format = string.format
local setmetatable, rawget = setmetatable, rawget

---@class request
local request = {}

function request.get_host()
    return ngx_var.host
end
function request.get_query_string()
    return ngx_var.query_string
end
function request.get_query()
    return ngx_req.get_uri_args()
end
function request.get_remote_addr()
    return ngx_var.remote_addr
end
function request.get_platform()
    return useragent.parse_platform(request.get_header('user_agent'))
end
function request.get_browser()
    return useragent.parse_browser(request.get_header('user_agent'))
end
function request.get_mobile()
    return useragent.parse_mobile(request.get_header('user_agent'))
end
function request.get_robot()
    return useragent.parse_robot(request.get_header('user_agent'))
end
---get_wechat
function request.get_wechat()
    return useragent.parse_wechat(request.get_header('user_agent'))
end
function request.get_remote_port()
    return ngx_var.remote_port
end
function request.get_raw_request()
    return ngx_var.request
end
---当前请求的文件路径名，比如/opt/nginx/www/test.php
---@return string
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
function request.get_args()
    return ngx_req.get_uri_args()
end
function request.get_path_info()
    return ngx_var.uri
end
function request.get_pid()
    return ngx_var.pid()
end
function request.get_server_version()
    return ngx_var.nginx_version
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

function request.set_body(self, value)
    if type(value) == "nil" then
        self._body = {}
    elseif type(value) == 'table' then
        util.foreach(value, function(val, k)
            local tval = type(val)
            if tval == 'table' then
                self._body[k] = tablex.imap(trim, val)
            else
                self._body[k] = trim(val)
            end
        end)
    end
end

function request.get_body(self)
    return self._body
end

function request.get_header(name)
    local headers = ngx_req.get_headers()
    if name then
        return headers[name]
    end
    return headers
end

---capture
---@param ctx app
---@return request
function request.capture(ctx)
    local localtime = ngx.localtime
    local req = {
        _body = {},
        header = ngx_req.get_headers(),
        params = {},
        ctx = ctx,
        routed_uri = "",
        cookie = setmetatable({}, {
            __index = function(_, name)
                return ngx.var['cookie_' .. name]
            end
        })
    }

    local new_request = setmetatable(req, {
        __index = function(_, key)
            local getter = rawget(request, "get_" .. key)
            if util.callable(getter) then
                return getter(req)
            elseif request[key] then
                return request[key]
            else
                return ngx_var[key]
            end
        end,
        __newindex = function(_, name, value)
            local setter = request["set_" .. name]
            if not util.callable(setter) then
                return nil
            end
            return setter(req, value)
        end
    })
    ctx.logger:write(string_format('\n[%s] %s %s', localtime(), new_request.get_remote_addr(), new_request.raw_request))
    return new_request
end

return request