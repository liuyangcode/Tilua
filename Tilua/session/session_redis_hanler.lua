
local cache = require('Tilua.cache')
local hanlder = nil
local log = require "Tilua.log"

local session_redis_hanler = {
    serializer = {
        encode = function(data)
            return require('cjson.safe').encode(data)
        end,
        decode = function(data)
            return require('cjson.safe').decode(data)
        end
    }
}
function session_redis_hanler.open()
    hanlder = cache():instance({
        type = 'redis',
        host = '172.17.0.1',
        port = 6379
    })
    return true
end

function session_redis_hanler.close()
    return true
end
function session_redis_hanler.read(id, gc_maxlifetime)
    local val, err = hanlder:get('ACCESSTOKEN' .. id, true)
    return val or ''
end
function session_redis_hanler.write(id, val, gc_maxlifetime)
    log.record(log.ERR, 'session_redis_hanler.write', id, val, gc_maxlifetime)
    local val, err = hanlder:set('ACCESSTOKEN' .. id, val, gc_maxlifetime)
    return val
end
function session_redis_hanler.destroy(name, id)
    local ok, err = hanlder:del(name .. id)
    log.record(log.ERR, 'session_redis_hanler.destroy', name, id)
    return ok
end
function session_redis_hanler.gc()
    return true
end

function session_redis_hanler.create_sid()

end

function session_redis_hanler.validate_sid(id)
    return id
end
function session_redis_hanler.updateTimestamp(id, val, gc_maxlifetime)
    log.record(log.ERR, 'session_redis_hanler.updateTimestamp', id, val, gc_maxlifetime)
    local val, err = hanlder:expire('ACCESSTOKEN' .. id, gc_maxlifetime)
    return true
end

return session_redis_hanler