local setmetatable,require = setmetatable,require

---@class session_redis_hanler
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

function session_redis_hanler.open(self)
    return true
end

function session_redis_hanler.close(self)
    return true
end
function session_redis_hanler.read(self,name, id, gc_maxlifetime)
    local val, err = self.handler:get(name .. id, true)
    return val or ''
end
function session_redis_hanler.write(self,name, id, val, gc_maxlifetime)
    self.log:debug('session_redis_hanler.write sessionid:', id," values:", val," lifetime:", gc_maxlifetime)
    local val, err = self.handler:set(name .. id, val, gc_maxlifetime)
    return val
end
function session_redis_hanler.destroy(self,name, id)
    local ok, err = self.handler:del(name .. id)
    self.log:error('session_redis_hanler.destroy', name, id)
    return ok
end
function session_redis_hanler.gc(self)
    return true
end

function session_redis_hanler.create_id(self)

end

function session_redis_hanler.validate_id(self,id)
    return id
end
function session_redis_hanler.update_timestamp(self,name, id, val, gc_maxlifetime)
    self.log:error( 'session_redis_hanler.updateTimestamp', id, val, gc_maxlifetime)
    local val, err = self.handler:expire(name .. id, gc_maxlifetime)
    return true
end

function session_redis_hanler.new(ctx)
    return setmetatable({
        log = ctx.logger,
        handler = ctx.cache.redis
    }, {
        __index = session_redis_hanler
    })
end

return session_redis_hanler