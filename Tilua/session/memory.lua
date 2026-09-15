--- In-memory session save handler (dev / tests; per-worker only)
local cjson = require("cjson.safe")

local store = {}

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
    return true
end

function M:close()
    return true
end

local function key(name, id)
    return (name or "sess:") .. id
end

function M:read(name, id, gc_maxlifetime)
    local k = key(name, id)
    local entry = store[k]
    if not entry then
        return ""
    end
    local ttl = tonumber(gc_maxlifetime) or 3600
    if entry.expire and entry.expire < ngx.time() then
        store[k] = nil
        return ""
    end
    return entry.val or ""
end

function M:write(name, id, val, gc_maxlifetime)
    local ttl = tonumber(gc_maxlifetime) or 3600
    store[key(name, id)] = {
        val = val,
        expire = ngx.time() + ttl,
    }
    return true
end

function M:destroy(name, id)
    store[key(name, id)] = nil
    return true
end

function M:gc(maxlifetime, _num)
    local now = ngx.time()
    for k, entry in pairs(store) do
        if entry.expire and entry.expire < now then
            store[k] = nil
        end
    end
    return true
end

function M:create_id()
    return nil
end

function M:validate_id(id)
    return type(id) == "string" and #id >= 8
end

function M:update_timestamp(name, id, val, gc_maxlifetime)
    local k = key(name, id)
    local entry = store[k]
    if not entry then
        return false
    end
    entry.expire = ngx.time() + (tonumber(gc_maxlifetime) or 3600)
    if val then
        entry.val = val
    end
    return true
end

function M.new(ctx)
    return setmetatable({
        log = ctx and ctx.logger,
        serializer = M.serializer,
    }, { __index = M })
end

return M
