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

local function get_boundary(content_type)
    local boundary = string.match(content_type, ";%s*boundary=([^,;]+)")
    boundary = strip(boundary, '"')

    return boundary
end
local function is_multipart(content_type)
    return string_startsWith(content_type, 'multipart/form-data')
end

---parse_disposition_headers
---@param headers table
local function parse_disposition_headers(headers)
    local name, filename, type, error, encoding
    map(function(v)
        if string_startsWith(v, "Content-Disposition") then
            -- file
            local ct, field, file_fields = pl_utils.unpack(split(v, ";"))
            ct = split(ct, ":")
            if ct[2] == " form-data" then
                if field then
                    field = split(field, "=")
                    name = strip(field[2], "\"")
                end
                if file_fields then
                    file_fields = split(file_fields, "=")
                    filename = strip(file_fields[2], "\"")
                end
            end
        elseif string_startsWith(v, "Content-Type") then
            local ct, charset = pl_utils.unpack(split(v, ";"))
            ct = split(ct, ":")
            type = strip(ct[2])
            if charset and string_startsWith(charset, 'charset') then
                charset = split(charset, "=")
                encoding = charset[2]
            else
                encoding = "utf8"
            end
        elseif string_startsWith(v, "Content-Transfer-Encoding") then
        end
    end, headers)
    return {
        name = name,
        origin_filename = filename,
        type = type or "text/plain",
        error = error,
        charset = encoding
    }
end

local function get_limit_size(typ)
    local limit_size = _ctx.config.multipart[typ]
    if util.is_number(limit_size) then
        return limit_size
    elseif util.is_string(limit_size) then
        limit_size = string.lower(limit_size)
        limit_size = string.gsub(limit_size, 'mb', '000000')
        limit_size = string.gsub(limit_size, 'kb', '000')
        return tonumber(limit_size)
    end
end

local function init_request_args()
    _get = req.get_uri_args() or {}
    _method = var.request_method
    if request.header.content_type then
        if string.sub(request.header.content_type, 1, 33) == 'application/x-www-form-urlencoded' then
            read_body()
            local post = req.get_post_args()
            _post = util.json_decode(post) or post or {}
        elseif is_multipart(request.header.content_type) then
            local boundary = get_boundary(request.header.content_type)
            local chunk_size = _ctx.config.multipart.chunk_size
            if boundary then
                local sock, err = req.socket()
                if not sock then
                    assert(sock, "ngx.req.socket init failed " .. err)
                end

                local read_line, err = sock:receiveuntil("\r\n")
                local read_post_body, _ = sock:receiveuntil("\r\n--" .. boundary)
                if not read_line then
                    return nil, err
                end
                local upload_tmp_dir = _ctx.config.multipart.tmpdir
                if not path_exists(upload_tmp_dir) then
                    makepath(upload_tmp_dir)
                end

                local multiparts = {}
                while true do
                    local preamble, _ = read_line()
                    if not preamble or string.sub(preamble, #preamble - 1) == '--' then
                        break
                    else
                        local disposition_headers = {}
                        while true do
                            local header, _ = read_line()
                            if header == "--" .. boundary .. "--" or header == "" or not header then
                                break
                            else
                                disposition_headers[#disposition_headers + 1] = header
                            end
                        end
                        if #disposition_headers == 0 then
                            break
                        end
                        local part = parse_disposition_headers(disposition_headers)
                        if #part.name > _ctx.config.multipart.field_name_size then
                            part.error = "Reach field_name_size limit"
                        else
                            local uuid = util.uuid()
                            local body, _ = read_post_body(chunk_size)
                            if (not body or #body < get_limit_size("field_value_size_in_memory")) and not part.origin_filename then
                                part.value = body or ""
                            else
                                local ext = path.extension(part.origin_filename)
                                if not tablex.find(_ctx.config.multipart.whitelist, ext) and not tablex.find(_ctx.config.multipart.file_extensions, ext) then
                                    part.error = "Invalid filename: " .. part.origin_filename
                                else
                                    local upload_file_tmp = io.open(upload_tmp_dir .. uuid, 'a+')
                                    upload_file_tmp:write(body)
                                    while true do
                                        body, _ = read_post_body(chunk_size)
                                        if not body then
                                            upload_file_tmp:close()
                                            part.filename = upload_tmp_dir .. uuid
                                            break
                                        else
                                            upload_file_tmp:write(body)
                                            part.size = upload_file_tmp:seek("end")
                                            if part.origin_filename and part.size > get_limit_size('file_size') then
                                                part.error = "Request file too large, please check multipart config"
                                                upload_file_tmp:close()
                                                break
                                            elseif not part.origin_filename and part.size > get_limit_size('field_size') then
                                                part.error = "Reach field_size limit, please check multipart config"
                                                upload_file_tmp:close()
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        multiparts[#multiparts + 1] = part
                    end
                end
                util.dump(multiparts)
            end
        end
    else
        local filename = req.get_body_file()
        if filename then
            local content = pl_utils.readfile(filename)
            if content then
                _post = {
                    content
                }
            end
        end
    end
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
    init_request_args()
    return request
end

return request