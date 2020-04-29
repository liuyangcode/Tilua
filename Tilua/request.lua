local ngx = ngx
local var = ngx.var

local req = ngx.req
local util = require("Tilua.util")

local routed_uri
---@class request
local request = {}
---@type app
local _ctx = nil
local _session = nil
local _headers = nil
local _body = {}
local _path_params = {}
local _cookie = setmetatable({}, {
    __index = function(t, name)
        return var['cookie_' .. name]
    end
})
function request.init_context(ctx)
    _ctx = ctx
    return request
end
---getter
---@param t request
---@param key string
function request.getter(t, key)

    local getter = rawget(request, "get_" .. key)
    if util.callable(getter) then

        return getter()
    elseif var[key] then
        return var[key]
    end
    return nil
end
function request.get_host()
    return var.host
end
function request.get_query_string()
    return var.query_string
end
function request.get_remote_addr()
    return var.remote_addr
end
function request.get_remote_port()
    return var.remote_port
end
function request.get_raw_request()
    return var.request
end
---当前请求的文件路径名，比如/opt/nginx/www/test.php
---@return string
function request.get_filename()
    return var.request_filename
end
function request.get_document_root()
    return var.document_root
end
function request.get_scheme()
    return var.scheme
end
function request.get_method()
    return var.request_method
end
function request.get_uri()
    return var.request_uri
end
function request.get_path_info()
    return var.uri
end
function request.get_pid()
    return var.pid
end
function request.get_server_version()
    return var.nginx_version
end
function request.get_hostname()
    return var.hostname
end
function request.get_server_name()
    return var.server_name
end
function request.get_params()
    return _path_params
end

function request.get_server_port()
    return var.server_port
end
function request.get_server_protocol()
    return var.server_protocol
end

function request.setter(t, key, value)
    local setter = request["set_" .. key]
    assert(util.callable(setter), "request cannot find property " .. key)
    return setter(value)
end
function request.set_params(params)
    _path_params = params
end
function request.set_body(value)
    if type(value) == "nil" then
        _body = {}
    elseif type(value) == 'table' then
        util.foreach(value, function(val, k)
            _body[k] = val
        end)
    end
end

function request.get_body()
    return _body
end

function request.set_routed_uri(uri)
    routed_uri = uri
end

function request.get_routed_uri()
    return routed_uri
end

function request.get_cookie(name)
    if not name then
        return _cookie
    end
    return var['cookie_' .. name]
end

function request.get_session()
    return _session
end

function request.set_session(session)
    _session = session
end

function request.get_header(name)
    if name then
        return _headers[name]
    end
    return _headers
end

function request.capture()
    _headers = req.get_headers()
    return setmetatable(request, {
        __index = request.getter,
        __newindex = request.setter
    })
end
return request