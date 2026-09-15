--- Tilua.session
--- Optimized session core (v0.2.2)
--- Consistent colon-style API, safer GC, fixed encode/decode bugs,
--- optional lazy write, stronger id validation.

local ngx = ngx
local ngx_time = ngx.time
local ngx_cookie_time = ngx.cookie_time
local format = string.format
local type = type
local helpers = require("Tilua.core.helpers")

local session = {}
session.__index = session

-- session_status: -1 not ready, 0 closed, 1 active
local STATUS_DISABLED = -1
local STATUS_CLOSED   = 0
local STATUS_ACTIVE   = 1

local function default_random_id()
    local ok, util = pcall(require, "Tilua.utils.util")
    if ok and util.random_string then
        return util.random_string()
    end
    -- fallback: md5 of time + random
    return ngx.md5(tostring(ngx.now()) .. tostring(math.random(1, 1e9)))
end

--- Validate session id shape (non-empty, reasonable charset/length)
function session:valid_key(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    if #key < 8 or #key > 128 then
        return false
    end
    -- allow hex / base64url-ish ids
    if not key:match("^[%w%-%_%=]+$") then
        return false
    end
    return true
end

function session:create_id()
    if self.save_handler and self.save_handler.create_id then
        local id = self.save_handler:create_id()
        if id and self:valid_key(id) then
            return id
        end
    end
    return default_random_id()
end

--- Probabilistic GC; avoid reseeding RNG every request
function session:gc(immediate)
    if not self.save_handler or not self.save_handler.gc then
        return
    end
    if immediate then
        self.save_handler:gc(self.config.gc_maxlifetime, -1)
        return
    end
    local prob = self.config.gc_probability or 0
    local divisor = self.config.gc_divisor or 100
    if prob <= 0 or divisor <= 0 then
        return
    end
    -- use ngx.worker.pid + time bits as entropy without math.randomseed
    local n = (ngx.now() * 1000 + ngx.worker.pid()) % divisor
    if n < prob then
        if self.log then
            self.log:debug("session gc triggered")
        end
        self.save_handler:gc(self.config.gc_maxlifetime, -1)
    end
end

function session:track_init()
    self.session_vars = ""
    self._session = {}
    self._dirty = false
end

function session:set(name, value)
    if type(name) == "string" then
        self._session[name] = value
        self._dirty = true
    elseif type(name) == "table" then
        for k, v in pairs(name) do
            self._session[k] = v
        end
        self._dirty = true
    end
    return self
end

function session:unset(name)
    if type(name) == "string" then
        self._session[name] = nil
        self._dirty = true
    elseif type(name) == "table" then
        for _, key in ipairs(name) do
            self._session[key] = nil
        end
        self._dirty = true
    end
    return self
end

function session:get(name)
    return self._session[name]
end

function session:all()
    return self._session
end

function session:encode(data)
    local ser = self.serialize_handler
    assert(ser and ser.encode, "session serializer.encode missing")
    return ser.encode(data)
end

function session:decode(val)
    local ser = self.serialize_handler
    assert(ser and ser.decode, "session serializer.decode missing")
    local ok, result = pcall(ser.decode, val)
    if not ok or result == false or result == nil then
        self:destroy()
        self:track_init()
        return {}
    end
    return result
end

function session:destroy()
    if self.session_status ~= STATUS_ACTIVE then
        return false
    end
    if self.id and self.save_handler and self.save_handler.destroy then
        self.save_handler:destroy(self.config.name, self.id)
    end
    self:track_init()
    self.id = nil
    self.send_cookie = self.config.use_cookies and 1 or 0
    return true
end

function session:abort()
    if self.session_status == STATUS_ACTIVE then
        if self.save_handler and self.save_handler.close then
            self.save_handler:close()
        end
        self.session_status = STATUS_CLOSED
        return true
    end
    return false
end

function session:reset_id()
    if not self.id then
        return false
    end
    if self.config.use_cookies and self.send_cookie and self.send_cookie ~= 0 then
        self:send_cookie_header()
        self.send_cookie = 0
    end
    return true
end

function session:init()
    self.session_status = STATUS_ACTIVE

    if self.save_handler.open and self.save_handler:open() == false then
        self:abort()
        return false
    end

    if not self.id then
        self.id = self:create_id()
        if not self.id then
            self:abort()
            return false
        end
        if self.config.use_cookies then
            self.send_cookie = 1
        end
    elseif self.config.use_strict_mode
        and self.save_handler.validate_id
        and self.save_handler:validate_id(self.id) == false then
        self.id = self:create_id()
        if self.config.use_cookies then
            self.send_cookie = 1
        end
    end

    if not self:reset_id() then
        self:abort()
        return false
    end

    self:track_init()

    local val = ""
    if self.save_handler.read then
        local ok, data = pcall(self.save_handler.read, self.save_handler, self.config.name, self.id, self.config.gc_maxlifetime)
        if not ok then
            if self.log then
                self.log:error("session read failed: ", tostring(data))
            end
            self:abort()
            return false
        end
        val = data or ""
    end

    self:gc(false)

    if type(val) == "string" and #val > 0 then
        if self.config.lazy_write and self.config.lazy_write > 0 then
            self.session_vars = val
        end
        self._session = self:decode(val)
        self._dirty = false
    end
    return true
end

function session:start(request)
    if self.log then
        self.log:debug("session start name=", self.config.name)
    end

    if self.session_status == STATUS_ACTIVE then
        return true
    end

    if not self.save_handler then
        if self.log then
            self.log:error("session save_handler missing")
        end
        return false
    end

    if not self.serialize_handler then
        -- default JSON serializer
        local cjson = require("cjson.safe")
        self.serialize_handler = {
            encode = function(d) return cjson.encode(d) or "{}" end,
            decode = function(d) return cjson.decode(d) end,
        }
    end

    self.session_status = STATUS_CLOSED
    self.send_cookie = (self.config.use_cookies or self.config.use_only_cookies) and 1 or 0

    -- resolve id from cookie / body / header
    self.id = nil
    if self.config.use_cookies and request and request.cookie then
        self.id = request.cookie[self.config.name]
        if self.id then
            self.send_cookie = 0
        end
    elseif not self.config.use_only_cookies and request then
        local body = request.body or request._body
        local header = request.header
        if type(body) == "table" then
            self.id = body[self.config.name]
        end
        if not self.id and type(header) == "table" then
            self.id = header[self.config.name]
        end
        if self.id then
            self.send_cookie = 0
        end
    end

    -- optional referer check
    local check = self.config.referer_check
    if self.id and check and check ~= "" and request and request.header then
        local referer = request.header.referer or request.header.Referer
        if referer and not string.find(referer, check, 1, true) then
            self.id = nil
        end
    end

    if self.id and not self:valid_key(self.id) then
        self.id = nil
    end

    if not self:init() then
        self.session_status = STATUS_CLOSED
        self.id = nil
        return false
    end
    return true
end

function session:save_current_state(write)
    if not write then
        if self.save_handler and self.save_handler.close then
            self.save_handler:close()
        end
        return true
    end

    if type(self._session) ~= "table" then
        return false
    end

    local val = self:encode(self._session)
    if not val or val == "" then
        val = "{}"
    end

    local ok, ret, err
    -- skip write if lazy and unchanged
    if self.config.lazy_write and self.config.lazy_write > 0
        and not self._dirty
        and self.session_vars
        and val == self.session_vars
        and self.save_handler.update_timestamp then
        ok, ret = pcall(self.save_handler.update_timestamp, self.save_handler, self.config.name, self.id, val, self.config.gc_maxlifetime)
    else
        ok, ret = pcall(self.save_handler.write, self.save_handler, self.config.name, self.id, val, self.config.gc_maxlifetime)
    end

    if not ok then
        if self.log then
            self.log:error("session write failed: ", tostring(ret))
        end
        return false
    end

    self.session_vars = val
    self._dirty = false

    if self.save_handler and self.save_handler.close then
        self.save_handler:close()
    end
    return ret ~= false
end

function session:flush(write)
    if self.session_status == STATUS_ACTIVE then
        self:save_current_state(write and true or false)
        self.session_status = STATUS_CLOSED
        return true
    end
    return false
end

function session:close()
    return self:flush(true)
end

function session:cookie_to_send()
    return self._cookies
end

function session:send_cookie_header()
    if not self.id then
        return false
    end
    local cookie = require("Tilua.http.cookie")
    local expires_min = tonumber(self.config.cookie_expires) or 0
    local max_age = nil
    if expires_min > 0 then
        max_age = expires_min * 60 -- historical config unit: minutes
    end
    self._cookies = cookie.build({
        name = self.config.name,
        value = self.id,
        path = self.config.cookie_path or "/",
        domain = self.config.cookie_domain,
        max_age = max_age,
        httponly = self.config.cookie_http_only ~= false,
        secure = self.config.cookie_secure,
        samesite = self.config.cookie_same_site or self.config.cookie_samesite or "Lax",
        raw = true,
    })
    return true
end


-- keep old name used by middleware
session.send_cookie = session.send_cookie_header

local function new(_, cfg, ctx)
    cfg = cfg or {}
    local save_handler = cfg.save_handler
    local serialize_handler = nil
    if type(save_handler) == "table" then
        serialize_handler = save_handler.serializer
    end

    local sess = {
        log = ctx and ctx.logger or nil,
        id = nil,
        session_status = STATUS_CLOSED,
        session_vars = "",
        send_cookie = 1,
        _session = {},
        _cookies = nil,
        _dirty = false,
        save_handler = save_handler,
        serialize_handler = serialize_handler or cfg.serialize_handler,
        config = cfg,
    }
    return setmetatable(sess, session)
end

setmetatable(session, { __call = new })

return session
