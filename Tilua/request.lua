local ngx = ngx
local var = ngx.var

local class = require('pl.class')
local req = ngx.req
local read_body = req.read_body
local util = require("Tilua.util")
local pl_utils = require("pl.utils")
local strip = require("pl.stringx").strip

local path = require "pl.path"
local dirname = path.dirname
local getmtime = path.getmtime

local makepath = require "pl.dir".makepath
local path_exists = path.exists


local _request = nil
local routed_uri
---@class request
local request = class()

function request:_init()
    self.headers = req.get_headers()
    self:catch(function(_, name)
        return self:magic(name)
    end)
    self:init_request_args()
end

---魔术方法
---@param name string
function request:magic(name)
    if rawget(self, 'get_' .. name) then
        return self['get_' .. name](self)
    elseif self['get_' .. name] then
        return self['get_' .. name](self)
    end
end

---初始化输入变量
function request:init_request_args()
    self.get = req.get_uri_args() or {}
    self.method = var.request_method
    if self.header.content_type then
        if string.sub(self.header.content_type, 1, 33) == 'application/x-www-form-urlencoded' then
            read_body()
            local post = req.get_post_args()
            self.post = util.json_decode(post) or post or {}
        elseif string.sub(self.header.content_type, 1, 19) == 'multipart/form-data' then
            local boundary = string.match(string.sub(self.header.content_type, 20), ";%s*boundary=([^,;]+)")
            local chunk_size = 1024
            if boundary then
                boundary = strip(boundary, '"')
                local sock, err = req.socket()
                if not sock then
                    assert(sock, "ngx.req.socket init failed " .. err)
                end

                local read_line, err = sock:receiveuntil("\r\n")
                local read_post_body, _ = sock:receiveuntil("\r\n--"..boundary)
                if not read_line then
                    return nil, err
                end
                local upload_tmp_dir = '/usr/local/openresty/lua/Test/tmp/'
                if not path_exists(upload_tmp_dir) then
                    makepath(upload_tmp_dir)
                end

                local file_index = 1
                while true do
                    local preamble, _ = read_line()
                    if  not preamble or string.sub(preamble,#preamble-1 ) == '--' then
                        break
                    else
                        while true do
                            local header, _ = read_line()
                            if header == "" or not header then
                                break
                            else
                                util.dump(header)
                            end
                        end
                        local file,_  = io.open(upload_tmp_dir..file_index,'a+')
                        while true do
                            local body, _ = read_post_body(chunk_size)
                            if not body then
                                file:close()
                                util.dump(upload_tmp_dir..file_index)
                                break
                            else
                                file:write(body)
                            end
                        end
                    end
                    file_index = file_index + 1
                end
            end
        end
    else
        local filename = req.get_body_file()
        if filename then
            local content = pl_utils.readfile(filename)
            if content then
                self.post = {
                    content
                }
            end
        end
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
    if name then
        return self.headers[name]
    end
    return self.headers
end

function request.capture()
    if not _request then
        _request = request()
    end
    return _request
end

return request