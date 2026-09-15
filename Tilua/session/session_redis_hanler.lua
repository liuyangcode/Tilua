--- Redis session save handler (filename kept for backward compatibility)
--- Prefer: Tilua.session.redis  (alias provided)

local setmetatable = setmetatable
local cjson = require("cjson.safe")

local M = {
    serializer = {
        encode = function(data)
            return cjson.encode(data) or "{}"
        end,
        decode = function(data)
            if not data or data == "" then
                return {}
            end
            return cjson.decode(data)
        end,
    },
}

function M:open()
    return self.handler ~= nil
end

function M:close()
    -- connection pool: nothing to close per-request
    return true
end

local function key(name, id)
    return (name or "sess:") .. id
end

function M:read(name, id, _gc_maxlifetime)
    if not self.handler then
        return ""
    end
    local val, err = self.handler:get(key(name, id), true)
    if err and self.log then
        self.log:error("session redis read error: ", err)
    end
    return val or ""
end

function M:write(name, id, val, gc_maxlifetime)
    if not self.handler then
        return false
    end
    local ttl = tonumber(gc_maxlifetime) or 3600
    if self.log then
        self.log:debug("session redis write id=", id, " ttl=", ttl)
    end
    local result, err = self.handler:set(key(name, id), val, ttl)
    if err then
        if self.log then
            self.log:error("session redis write error: ", err)
        end
        return false
    end
    return result ~= false
end

function M:destroy(name, id)
    if not self.handler then
        return false
    end
    local ok, err = self.handler:del(key(name, id))
    if err and self.log then
        self.log:error("session redis destroy error: ", err)
    end
    return ok and true or false
end

function M:gc(_maxlifetime, _num)
    -- Redis TTL handles expiry; no scan needed
    return true
end

function M:create_id()
    return nil -- let session core generate
end

function M:validate_id(id)
    return type(id) == "string" and #id >= 8
end

function M:update_timestamp(name, id, _val, gc_maxlifetime)
    if not self.handler then
        return false
    end
    local ttl = tonumber(gc_maxlifetime) or 3600
    local ok, err = self.handler:expire(key(name, id), ttl)
    if err and self.log then
        self.log:error("session redis expire error: ", err)
    end
    return ok ~= false
end

function M.new(ctx)
    local cache = ctx.cache
    local handler = nil
    if cache then
        -- prefer redis instance from cache manager
        if cache.redis then
            handler = cache.redis
        elseif type(cache.instance) == "function" then
            local ok, inst = pcall(cache.instance, cache, "redis")
            if ok then
                handler = inst
            end
        end
    end
    return setmetatable({
        log = ctx.logger,
        handler = handler,
        serializer = M.serializer,
    }, { __index = M })
end

return M
