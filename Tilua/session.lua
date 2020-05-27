local ngx = ngx
local md5 = ngx.md5
local ngx_cookie_time = ngx.cookie_time
local format = string.format
local ngx_time = ngx.time
---@class session
local session = {}

---检查session id 是否有效
---@param key string
---@return boolean
function session.valid_key(self, key)
    return true
end

---垃圾回收
---@param immediate boolean 是否立即清理
function session.gc(self, immediate)
    local num = -1
    if self.save_handler then
        if immediate then
            self.save_handler:gc(self.config.gc_maxlifetime, num)
            return num
        end
        math.randomseed(tostring(ngx.now()):reverse():sub(1, 7))
        local nrand = self.config.gc_divisor * math.random()
        if self.config.gc_probability > 0 and nrand < self.config.gc_probability then
            self.log:debug('start garbage collet')
            self.save_handler:gc(self.config.gc_maxlifetime, num)
        end
    end
end
---初始化记录
function session.track_init(self)
    self.session_vars = '{}'
    self._session = {}
end
---set
---@param name any
---@param value any
---@return boolean
function session.set(self, name, value)
    if type(name) == string then
        self._session[name] = value
    elseif type(name) == 'table' then
        for key, val in pairs(name) do
            self._session[key] = val
        end
    else
        return false
    end
    return true
end

---get
---@param name string
---@return any
function session.get(self, name)
    return self._session[name] ~= nil and self._session[name] or nil
end

function session.encode(self, data)
    if self.session_vars then
        assert(self, self.save_handler.serializer, 'Unknown session.serialize_handler. Failed to encode session object')
        return self.save_handler.serializer.encode(data)
    end
end
---销毁session
function session.destroy(self)
    if self.session_status ~= 1 then
        return false
    end
    if self.id and not self.save_handler:destroy(self.config.name, self.id) then
        return false
    end
    return true
end

---decode
---@param self table
---@param val cache
function session.decode(self, val)
    assert(self.save_handler.serializer, 'Unknown session.serialize_handler. Failed to decode session object')
    local result = self.save_handler.serializer.decode(val)
    if result == false then
        session.destroy()
        session.track_init()
        return false
    end
    return result
end
---session启动
---@param request request
function session.start(self, request)
    self.log:debug('session start with session name ',self.config.name)
    if self.session_status == 1 then
        return false
    elseif self.session_status == -1 then
        if not self.save_handler then
            self.log:record(self.log.ERR, 'Cannot find save handler - session startup failed')
        end
        if not self.serialize_handler then
            self.log:record(self.log.ERR, "Cannot find serialization handler - session startup failed")
        end
        self.session_status = 0
    end
    if self.session_status == 0 then
        self.send_cookie = self.config.use_cookies or self.config.use_only_cookies
    end
    if self.config.use_cookies then
        self.id = request.cookie[self.config.name]
        if self.id then
            self.send_cookie = 0
        end
    elseif not self.config.use_only_cookies then
        self.id = request.body[self.config.name] or request.header[self.config.name]
        if self.id then
            self.send_cookie = 0
        end
    end
    local referer = request.header.referer
    if self.id and referer and not string.find(referer, self.config.referer_check, 1, true) then
        self.id = nil
    end
    if not session.valid_key(self, self.id) then
        self.id = nil
    end
    if not session.init(self) then
        self.session_status = 0
        if self.id then
            self.id = nil
        end
        return false
    end
    return true
end

function session.reset_id(self)
    if not self.id then
        assert(false, "Cannot set session ID - session ID is not initialized")
    end
    if self.config.use_cookies and self.send_cookie then
        session.send_cookie(self)
        self.send_cookie = 0
    end
    return true
end

function session.init(self)
    self.session_status = 1
    if self.save_handler:open() == false then
        session.abort(self)
        return false
    end
    if not self.id then
        self.id = session.create_id(self)
        if not self.id then
            session.abort(self)
            return false
        end
        if self.config.use_cookies then
            self.send_cookie = 1
        end
    elseif self.config.use_strict_mode and
            self.save_handler.validate_id and
            self.save_handler:validate_id(self.id) == false then
        self.id = self.save_handler:create_id()
        if not self.id then
            self.id = session.create_id(self)
        end
        if self.config.use_cookies then
            self.send_cookie = 1
        end
    end
    if session.reset_id(self) == false then
        session.abort(self)
        return false
    end
    session.track_init(self)
    local val = self.save_handler:read(self.config.name, self.id, self.config.gc_maxlifetime)
    if val == false then
        session.abort(self)
        return false
    end
    session.gc(self, false)
    self.session_vars = {}
    if #val > 0 then
        if self.config.lazy_write > 0 then
            self.session_vars = val
        end
        self._session = session.decode(self, val)
    end
    return true
end
---session关闭
function session.close(self)
    self.flush(self, 1)
end

function session.abort(self)
    if self.session_status == 1 then
        self.save_handler:close()
        self.session_status = 0
        return true
    end
    return false
end

---flush
---@param self table
---@param write string
function session.flush(self, write)
    if self.session_status == 1 then
        session.save_current_state(self, write)
        self.session_status = 0
        return true
    end
    return false
end

function session.save_current_state(self, write)
    local ret = false
    if write then
        if type(self._session) == 'table' then
            local val = session.encode(self, self._session)
            if val ~= '{}' then
                if self.config.lazy_write and self.session_vars and self.save_handler.update_timestamp
                        and #val == #self.session_vars and val == self.session_vars then
                    ret = self.save_handler:update_timestamp(self.config.name, self.id, val, self.config.gc_maxlifetime)
                else
                    ret = self.save_handler:write(self.config.name, self.id, val, self.config.gc_maxlifetime)
                end
            else
                ret = self.save_handler:write(self.config.name, self.id, '{}', self.config.gc_maxlifetime)
            end
        end
        if not ret then
            assert(false, "Failed to write session data using user defined save handler.")
        end
    end
    if self.save_handler then
        self.save_handler:close()
    end
end

function session.cookie_to_send(self)
    return self._cookies
end

---send_cookie
---@param self table
function session.send_cookie(self)
    local cookie_format = '%s=%s;path=%s;expires=%s;domain=%s;%s'
    self._cookies = format(cookie_format, self.config.name, self.id, self.config.cookie_path,
            self.config.cookie_expires > 0 and ngx_cookie_time(ngx_time() + 60 * self.config.cookie_expires) or 0, self.config.cookie_domain, self.config.cookie_http_only and 'httponly;' or '')
    return true
end

function session.new(cfg, ctx)
    local sess = {
        log = ctx.logger,
        id = nil,
        session_status = 0,
        session_vars = '',
        send_cookie = 1,
        _session = {},
        _cookies = {},
        save_handler = cfg.save_handler,
        serialize_handler = nil,
        config = cfg or nil
    }
    sess.serialize_handler = sess.save_handler.serializer

    return setmetatable(sess, {
        __index = session
    })
end

function session.create_id(self)
    return ngx.md5(ngx.var.remote_addr .. ngx.now() .. math.random(1, 10000000))
end

return session