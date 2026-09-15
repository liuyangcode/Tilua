--- Tilua.middleware
--- New canonical name for the middleware manager.
--- The old Tilua.midware remains as a compatibility alias.

local ngx = ngx
local lw_util = require("Tilua.utils.util")
local import  = lw_util.import
local helpers = require("Tilua.core.helpers")
local split = helpers.split
local map = helpers.map


local manager = {
    midwares = {},
    alias = {},
    midware_group = {},
}

local midware_group_parsed = {}

function manager.is_group(val)
    local mat = ngx.re.match(val, [[\[[a-zA-Z_0-9]+\]]])
    return mat ~= nil
end

local function get_shortname(name)
    return (name:gsub("%.", "_"))
end

function manager.instance(self, midware)
    local hash = lw_util.get_hash and lw_util.get_hash(midware) or table.concat(midware, "|")
    if self.midwares[hash] then
        return self.midwares[hash]
    end

    local midware_class, alias_name
    if manager.alias[midware[1]] then
        alias_name    = midware[1]
        midware_class = manager.alias[midware[1]]
    else
        midware_class = midware[1]
        alias_name    = get_shortname(midware_class)
    end

    local mid_class = import(midware_class)
    if not mid_class then
        error("middleware named '" .. tostring(midware[1]) .. "' not found")
    end

    local mid = mid_class(self.ctx, midware[2])
    if not mid.handle then
        error("middleware '" .. tostring(midware[1]) .. "' must implement handle()")
    end

    self.midwares[hash] = mid
    return mid
end

function manager.load(config)
    manager.midware_group = config.midware_group or config.middleware_group or {}
    manager.alias         = config.midware_alias or config.middleware_alias or {}
    return manager
end

function manager.get_group(name)
    if manager.is_group(name) then
        name = name:sub(2, #name - 1)
    end
    if midware_group_parsed[name] then
        return midware_group_parsed[name]
    end
    midware_group_parsed[name] = manager.parse(manager.midware_group[name])
    return midware_group_parsed[name]
end

function manager.group(name, midwares)
    if lw_util.is_string(midwares) then
        midwares = manager.parse(midwares)
    elseif lw_util.is_array(midwares) then
        midwares = map(function(v)
            return manager.parse(v)
        end, midwares)
    end
    manager.midware_group[name] = midwares
end

function manager.parse(val)
    if type(val) == "table" then
        return val
    end
    if type(val) ~= "string" then
        return {}
    end

    -- support "a|b|c" or "a,b,c"
    local parts = split(val, "[|,]")
    local result = {}
    for _, p in ipairs(parts) do
        p = (p:match("^%s*(.-)%s*$")) or p
        if p ~= "" then
            if manager.is_group(p) then
                local group = manager.get_group(p)
                for _, g in ipairs(group) do
                    table.insert(result, g)
                end
            else
                table.insert(result, { p })
            end
        end
    end
    return result
end

-- constructor used by app
local function new(app)
    local m = setmetatable({
        ctx      = app,
        midwares = {},
    }, { __index = manager })
    return m
end

return setmetatable(manager, {
    __call = function(_, app)
        return new(app)
    end,
})
