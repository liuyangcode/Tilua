local ngx = ngx
local var = ngx.var

local class = require('pl.class')
local req = ngx.req
local read_body = req.read_body
local util = require("Tilua.util")
local pl_utils = require("pl.utils")
local strip = require("pl.stringx").strip
local split = require("pl.stringx").split
local string_startsWith = require("pl.stringx").startswith
local tablex = require("pl.tablex")

local map = tablex.map
local path = require "pl.path"
local dirname = path.dirname
local getmtime = path.getmtime

local makepath = require "pl.dir".makepath
local path_exists = path.exists

local _request = nil
local routed_uri
---@class request
local request = class()
---@type app
local _ctx = nil
local _method = nil
local _get = nil
local _post = nil
local _session = nil
local _headers = nil
function request.init_context(ctx)
    _ctx = ctx
    request.body = {}
    request.catch(request.magic)
    return request
end

function request:_init(ctx)
    assert(false, 'request cannot be instanced ')
    _ctx = ctx
    _headers = req.get_headers()
    request.catch(function(_, name)
        return request.magic(name)
    end)
    request.init_request_args()
end

---魔术方法
---@param name string
function request.magic(_, name)
    if rawget(request, 'get_' .. name) then
        return request['get_' .. name]()
    end
end
function request.get_method()
    return _method
end

function request.get_path_info()
    return var.uri
end
function request.set_routed_uri(uri)
    routed_uri = uri
end
function request.get_routed_uri()
    return routed_uri
end
function request.get_cookie(name)
    return var['cookie_' .. name]
end
---获取GET变量
---@param name string
function request.get(name)
    return _get[name]
end
---获取POST变量
---@param name string
function request.post(name)
    return _post[name]
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
    return request
end

return request