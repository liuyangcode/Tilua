local ngx = ngx
local md5 = ngx.md5
local re_match = ngx.re.match
local ngx_cookie_time = ngx.cookie_time
local format = string.format
local ngx_time = ngx.time
---@class session
local session = {}
local log = require('Tilua.log')
local id = nil
local session_status = 0
local session_vars = ''
local send_cookie = 1

local _session = {}
local _cookies = {}
---config
local use_strict_mode = true
local use_cookies = true
local gc_maxlifetime = 300
local gc_divisor = 100
local session_name = 'ACCESSTOKEN'
local save_handler = nil
local serialize_handler = nil
local use_only_cookies = true
local referer_check = ""
local lazy_write = 1
local gc_probability = 1
local cookie_path = '/'
local cookie_domain = 'centos-7'
local cookie_expires = 30
local cookie_http_only = true
---检查session id 是否有效
---@param key string
---@return boolean
function session.valid_key(key)
    return true
end

function session.set_save_handler(handler)
    save_handler = handler
end
---垃圾回收
---@param immediate boolean 是否立即清理
function session.gc(immediate)
    local num = -1
    if save_handler then
        if immediate then
            save_handler.gc(gc_maxlifetime, num)
            return num
        end
        math.randomseed(tostring(ngx.now()):reverse():sub(1, 7))
        local nrand = gc_divisor * math.random()
        if gc_probability > 0 and nrand < gc_probability then
            log.record(log.DEBUG, 'start garbage collet')
            save_handler.gc(gc_maxlifetime, num)
        end
    end
end
---初始化记录
function session.track_init()
    session_vars = '{}'
    _session = {}
end
---set
---@param name any
---@param value any
---@return boolean
function session.set(name, value)
    if type(name) == string then
        _session[name] = value
    elseif type(name) == 'table' then
        for key, val in pairs(name) do
            _session[key] = val
        end
    else
        return false
    end
    return true
end

---get
---@param name string
---@return any
function session.get(name)
    return _session[name] ~= nil and _session[name] or nil
end

function session.encode(data)
    if session_vars then
        assert(save_handler.serializer, 'Unknown session.serialize_handler. Failed to encode session object')
        return save_handler.serializer.encode(data)
    end
end
---销毁session
function session.destroy()
    if session_status ~= 1 then
        return false
    end
    if id and not save_handler.destroy(session_name, id) then
        return false
    end
    return true
end

function session.decode(val)
    assert(save_handler.serializer, 'Unknown session.serialize_handler. Failed to decode session object')
    local result = save_handler.serializer.decode(val)
    if result == false then
        session.destroy()
        session.track_init()
        return false
    end
    return result
end

function session.id()
    return id
end
function session.init_config(config)
    use_strict_mode = config.use_strict_mode
    use_cookies = config.use_cookies
    gc_maxlifetime = config.gc_maxlifetime
    gc_divisor = config.gc_divisor
    session_name = config.name
    use_only_cookies = config.use_only_cookies
    referer_check = config.referer_check
    lazy_write = config.lazy_write
    gc_probability = config.gc_probability
    cookie_path = config.cookie_path
    cookie_domain = config.cookie_domain
    cookie_expires = config.cookie_expires
    cookie_http_only = config.cookie_http_only
    local found = false
    found, save_handler = pcall(require, config.save_handler)
    assert(found, 'Cannot find save handler - session startup failed')
    serialize_handler = save_handler.serializer
end
---session启动
---@param request request
function session.start(request)
    log.record(log.DEBUG, 'session start with config')
    if session_status == 1 then
        return false
    elseif session_status == -1 then
        if not save_handler then
            log.record(log.ERR, 'Cannot find save handler - session startup failed')
        end
        if not serialize_handler then
            log.record(log.ERR, "Cannot find serialization handler - session startup failed")
        end
        session_status = 0
    end
    if session_status == 0 then
        send_cookie = use_cookies or use_only_cookies
    end
    if use_cookies then
        id = request.cookie[session_name]
        if id then
            send_cookie = 0
        end
    elseif not use_only_cookies then
        id = request.body[session_name] or request.header[session_name]
        if id then
            send_cookie = 0
        end
    end
    local referer = request.header.referer
    if id and referer and not string.find(referer, referer_check, 1, true) then
        id = nil
    end
    if not session.valid_key(id) then
        id = nil
    end
    if not session.init() then
        session_status = 0
        if id then
            id = nil
        end
        return false
    end
    return true
end

function session.reset_id()
    if not id then
        assert(false, "Cannot set session ID - session ID is not initialized")
    end
    if use_cookies and send_cookie then
        session.send_cookie()
        send_cookie = 0
    end
    return true
end
function session.init()
    session_status = 1
    if save_handler.open() == false then
        session.abort()
        return false
    end
    if not id then
        id = session.create_id()
        if not id then
            session.abort()
            return false
        end
        if use_cookies then
            send_cookie = 1
        end
    elseif use_strict_mode and
            save_handler.validate_id and
            save_handler.validate_id(id) == false then
        id = save_handler.create_id()
        if not id then
            id = session.create_id()
        end
        if use_cookies then
            send_cookie = 1
        end
    end
    if session.reset_id() == false then
        session.abort()
        return false
    end
    session.track_init()
    local val = save_handler.read(session_name, id, gc_maxlifetime)
    if val == false then
        session.abort()
        return false
    end
    session.gc(false)
    session_vars = {}
    if #val > 0 then
        if lazy_write > 0 then
            session_vars = val
        end
        _session = session.decode(val)
    end
    return true
end
---session关闭
function session.close()
    session.flush(1)
end

function session.abort()
    if session_status == 1 then
        save_handler.close()
        session_status = 0
        return true
    end
    return false
end

function session.flush(write)
    if session_status == 1 then
        session.save_current_state(write)
        session_status = 0
        return true
    end
    return false
end

function session.save_current_state(write)
    local ret = false
    if write then
        if type(_session) == 'table' then
            local val = session.encode(_session)
            if val ~= '{}' then
                if lazy_write and session_vars and save_handler.update_timestamp
                        and #val == #session_vars and val == session_vars then
                    ret = save_handler.update_timestamp(session_name, id, val, gc_maxlifetime)
                else
                    ret = save_handler.write(session_name, id, val, gc_maxlifetime)
                end
            else
                ret = save_handler.write(session_name, id, '{}', gc_maxlifetime)
            end
        end
        if not ret then
            assert(false, "Failed to write session data using user defined save handler.")
        end
    end
    if save_handler then
        save_handler.close()
    end
end

function session.cookie_to_send()
    return _cookies
end

function session.send_cookie()
    local cookie_format = '%s=%s;path=%s;expires=%s;domain=%s;%s'
    _cookies = format(cookie_format, session_name, id, cookie_path,
            cookie_expires > 0 and ngx_cookie_time(ngx_time() + 60 * cookie_expires) or 0, cookie_domain, cookie_http_only and 'httponly;' or '')
    return true
end

function session.create_id()
    return ngx.md5(ngx.var.remote_addr .. ngx.now() .. math.random(1, 10000000))
end

return session