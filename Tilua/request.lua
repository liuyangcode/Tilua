local ngx = ngx
local ngx_req = ngx.req
local ngx_var = ngx.var
local util = require("Tilua.util")
local string_format = string.format

---@class request
local request = {}

---@type app
local _path_params = {}

---getter
---@param t request
---@param key string
function request.getter(t, key)

    local getter = rawget(request, "get_" .. key)
    if util.callable(getter) then

        return getter()
    elseif ngx_var[key] then
        return ngx_var[key]
    end
    return nil
end
function request.get_host()
    return ngx_var.host
end
function request.get_query_string()
    return ngx_var.query_string
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
function request.get_path_info()
    return ngx_var.uri
end
function request.get_pid()
    return ngx_var.pid
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
function request.get_params()
    return _path_params
end

function request.get_server_port()
    return ngx_var.server_port
end
function request.get_server_protocol()
    return ngx_var.server_protocol
end

function request.setter(t, key, value)
    local setter = request["set_" .. key]
    if not util.callable(setter) then
        return nil
    end
    return setter(value)
end

function request.set_params(params)
    _path_params = params
end

function request.set_body(value)
    if not ngx.ctx.__request_body then
        ngx.ctx.__request_body = {}
    end
    if type(value) == "nil" then
        ngx.ctx.__request_body = {}
    elseif type(value) == 'table' then
        util.foreach(value, function(val, k)
            ngx.ctx.__request_body[k] = val
        end)
    end
end

function request.get_body()
    return ngx.ctx.__request_body
end

function request.set_routed_uri(uri)
    ngx.ctx.__request_routed_uri = uri
end

function request.get_routed_uri()
    return ngx.ctx.__request_routed_uri
end

function request.get_cookie(name)
    if not name then
        return setmetatable({}, {
            __index = function(_, name)
                return ngx.var['cookie_' .. name]
            end
        })
    end

    return ngx.var['cookie_' .. name]
end

function request.get_header(name)
    local headers = ngx_req.get_headers()
    if name then
        return headers[name]
    end
    return headers
end

function request.capture()
    local ctx = ngx.ctx.ctx
    local localtime = ngx.localtime
    ctx.logger:write(string_format('\n[%s] %s %s', localtime(), request.get_remote_addr(), request.get_raw_request()))
    return setmetatable(request, {
        __index = request.getter,
        __newindex = request.setter
    })
end

return request