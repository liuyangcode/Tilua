

local shdict = require "Tilua.cache".derive()
local ngx_shared = ngx.shared
local json = require("cjson.safe")
local commands = {
    --[["get",]] "get_stale", --[["set",]] "safe_set", "add", "safe_add", "replace", "delete", "incr", "lpush",
                 "rpush", "lpop", "rpop", "llen", "ttl", "expire", "flush_all", "flush_expired", "get_keys",
                 "capacity", "free_space"
}

function shdict:_init(config, ctx)
    self:super(ctx)
    self.config = config
    self.dict = ngx_shared[self.config.dict]
end

function shdict:get(name)
    if not name then
        return ''
    end
    local result, err = self:do_command('get', name)
    if not result or err then
        return nil, err
    end
    local jsonresult, err = json.decode(result)
    if jsonresult then
        return jsonresult
    end
    return result
end

function shdict:set(name, value, ...)
    if type(value) == 'table' then
        value = json.encode(value)
    end
    local result, err
    return self:do_command('set', name, value, ...)
end

function shdict:do_command(cmd, ...)
    assert(self.dict, 'nginx shared not loaded dict ')
    assert(self.dict[cmd], 'operation not found ' .. cmd)
    local result, err = (self.dict[cmd])(self.dict, ...)
    if not result or err then
        return nil, err
    end
    return result
end

for i = 1, #commands do
    local cmd = commands[i]
    shdict[cmd] = function(self, ...)
        return shdict.do_command(self, cmd, ...)
    end
end

return shdict