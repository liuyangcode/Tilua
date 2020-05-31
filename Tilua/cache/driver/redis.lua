local redis_c = require "resty.redis"
local lw_util = require('Tilua.util')

local commands = {
    "append", "bgsave", "blpop", "brpoplpush", "auth", "bitcount",
    "brpop", "client", "bgrewriteaof", "bitop", "config", "dbsize",
    "debug", "decr", "del", "discard", "echo", "eval",
    "exec", "expire", "expireat", "flushdb", --[[ "get", ]] "getrange",
    "getset", "hexists", "hget", "hincrby", "hincrbyfloat", "hlen",
    "hmget", "hset", "hsetnx", "incrby", "keys", "lastsave",
    "llen", "lpushx", "lset", "migrate", "monitor", "msetnx",
    "persist", "ping", "pttl", "publish", "quit", "randomkey",
    "restore", "rpop", "rpushx", "scan", "sdiff", "select",
    "setex", "shutdown", "sismember", "smembers", "spop", "sscan",
    "strlen", "sunionstore", "ttl", "type", "watch", "zcount",
    "zrange", "zrem", "zrevrange", "zscan", "zscore", "hmset",
    "hvals", "incrbyfloat", "lindex", "lpop", "lrange", "ltrim",
    "move", "multi", "pexpire", "psetex", --[[ "punsubscribe", ]]
    "rename", "info", "linsert", "lpush", "lrem", "mget",
    "mset", "object", "pexpireat", "psubscribe", "pubsub", "renamenx",
    "rpush", "save", "script", "setbit", "setrange", "sinterstore",
    "slowlog", "sort", "srem", "sunion", "time", "rpoplpush",
    "sadd", "scard", "sdiffstore", --[[  "set" , ]] "setnx", "sinter",
    "slaveof", "smove", "srandmember", --[[ "subscribe",  ]] "sync",
    --[[ "unsubscribe", ]] "zunionstore", "evalsha", "decrby", "dump",
    "exists", "flushall", "getbit", "hdel", "hgetall", "hkeys",
    "hscan", "incr", "zadd", "zincrby", "zrangebyscore", "zrank",
    "zremrangebyrank", "zremrangebyscore", "zrevrangebyscore",
    "zrevrank", "unwatch", "zcard", "zinterstore"
}

local redis = require "Tilua.cache".derive()
local function is_redis_null(res)
    if type(res) == "table" then
        for k, v in pairs(res) do
            if v ~= ngx.null then
                return false
            end
        end
        return true
    elseif res == ngx.null then
        return true
    elseif res == nil then
        return true
    end

    return false
end

function redis:_init(config, ctx)
    self:super(ctx)
    self.config = {
        timeout = config.timeout and config.timeout * 1000 or 1000,
        db_index = config.db_index or ctx.config.redis_db_index or 0,
        host = config.host or ctx.config.redis_host or '127.0.0.1',
        port = config.port or ctx.config.redis_port or 6379
    }
    self._reqs = ''
    self._redisc = false
    self.handler = {}
end

function redis:get_redis()
    if self._redisc then
        return self._redisc
    end
    local _redisc, err = redis_c:new()
    assert(_redisc, 'redis init failed' .. (err or ''))
    self._redisc = _redisc
    return self._redisc
end

function redis:connect_mod()
    self:get_redis():set_timeout(self.config.timeout)
    return self:get_redis():connect(self.config.host, self.config.port)
end
--加入连接池
function redis:set_keepalive_mod()
    return self:get_redis():set_keepalive(self.ctx.config.redis_pool_timeout * 1000, self.ctx.config.redis_pool_size)
end

function redis:init_pipeline()
    self._reqs = {}
end

function redis:commit_pipeline()
    local reqs = self._reqs

    if nil == reqs or 0 == #reqs then
        return {}, "no pipeline"
    else
        self._reqs = nil
    end

    local ok, err = self:connect_mod()
    assert(ok, 'redis ' .. self.config.host .. ' connect failed ' .. (err or ''))

    self:init_pipeline()
    for _, vals in ipairs(reqs) do
        local fun = self:get_redis()[vals[1]]
        table.remove(vals, 1)
        fun(self:get_redis(), unpack(vals))
    end

    local results, err = self:get_redis():commit_pipeline()
    if not results or err then
        return {}, err
    end

    if is_redis_null(results) then
        results = {}
        ngx.log(ngx.WARN, "is null")
    end

    self:set_keepalive_mod()

    for i, value in ipairs(results) do
        if is_redis_null(value) then
            results[i] = nil
        end
    end
    return results, err
end

function redis:get(name, raw)
    if not name then
        return ''
    end
    local result, err = self:do_command('get', name)

    if not result or err then
        return nil, err
    end
    if not raw then
        return lw_util.json_decode(result) or result
    end
    return result
end

function redis:set(name, value, expire)
    expire = expire or -1
    if type(value) == 'table' then
        value = lw_util.json_encode(value)
    end
    local result, err
    if expire > 0 then
        result, err = self:do_command('setex', name, expire, value)
    else
        result, err = self:do_command('set', name, value)
    end

    return result, err
end

function redis:do_command(cmd, ...)
    if self._reqs ~= '' and self._reqs then
        table.insert(self._reqs, { cmd, ... })
        return
    end
    local ok, err = self:connect_mod()
    if not ok then
        self.ctx.logger:error("redis connect failed ", err, " with config ", lw_util.json_encode(self.config))
        error(table.concat({ "redis connect failed ", err, " with config ", lw_util.json_encode(self.config) }), 2)
    end

    local fun = self:get_redis()[cmd]
    local result, err = fun(self:get_redis(), ...)
    if not result or err then
        return nil, err
    end

    if is_redis_null(result) then
        result = nil
    end
    self:set_keepalive_mod()
    return result, err
end

for i = 1, #commands do
    local cmd = commands[i]
    redis[cmd] = function(self, ...)
        return redis.do_command(self, cmd, ...)
    end
end

return redis
