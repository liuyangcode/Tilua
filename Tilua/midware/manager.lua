local ngx = ngx
local midware_sep = "|"
local midware_group = {}
local midware_group_parsed = {}
local lw_util = require('Tilua.util')
local map = require("pl.tablex").map
local split = require('pl.utils').split
local match = ngx.re.match
local string_gsub = string.gsub
local pcall = pcall
---@class midware_manager
local manager = {}
---@type app
local _ctx = nil
local _midwares = nil
local alias = nil
function manager.is_group(val)
    local mat, _ = match(val, '[[a-zA-Z_0-9]+]')
    return mat ~= nil
end

---init
---@param ctx app
function manager.init(ctx)
    if _ctx then
        return manager
    end
    _ctx = ctx
    _midwares = {}
    return setmetatable(manager, {
        __index = function(t, midware)
            if _midwares[midware] then
                return _midwares[midware]
            end
        end,
        __newindex = function(t, key, val)
            _midwares[key] = val
        end
    })
end

local function get_shortname(name)
    return string_gsub(name, '[.]', '_')
end

function manager.instance(midware)
    local midware_class = alias[midware[1]] or midware[1]
    local alias_name = ''
    if alias[midware[1]] then
        alias_name = midware[1]
        midware_class = alias[midware[1]]
    else
        midware_class = midware[1]
        alias_name = get_shortname(midware_class)
    end

    local ok, mid_class = pcall(require, midware_class)
    if not ok then
        assert(false, 'midware named ' .. midware[1] .. ' not found')
    end
    local mid =  mid_class(_ctx, midware[2])
    _midwares[mid.alias or alias_name] = mid
    assert(mid.handle, 'midware named:' .. midware[1] .. ' handle func required')
    return mid
end

function manager.load()
    midware_group = _ctx.config.midware_group
    alias = _ctx.config.midware_alias
end

---get_group
---@param name string
function manager.get_group(name)
    if manager.is_group(name) then
        name = string.sub(name, 2, #name - 1)
    end
    if midware_group_parsed[name] then
        return midware_group_parsed[name]
    end
    midware_group_parsed[name] = manager.parse(midware_group[name])
    return midware_group_parsed[name]
end
---创建中间件分组
---@param name string
---@param midwares table
function manager.group(name, midwares)
    if lw_util.is_string(midwares) then
        midwares = manager.parse(midwares)
    elseif lw_util.is_array(midwares) then
        midwares = map(function(v)
            return manager.parse(v)
        end, midwares)
    end
    midware_group[name] = midwares
end
---解析配置字符串到table
local function parse_config(config)
    config = split(config, ',')
    return map(function(val)
        val = split(val, '=')
        return {
            [val[1]] = val[2]
        }
    end, config)
end
---parse_midware_from_string
---@param midware_params string
---@return table
function manager.parse(midware_params)
    if not midware_params then
        return {}
    end
    if lw_util.is_string(midware_params) then
        local midware_str_arr = split(midware_params, midware_sep)
        local midware_arr = {}
        lw_util.foreach(midware_str_arr, function(v)
            if manager.is_group(v) then
                map(function(m)
                    table.insert(midware_arr, m)
                end, manager.get_group(v))
            else
                v = split(v, ':')
                if #v == 1 then
                    midware_arr[#midware_arr + 1] = {
                        v[1],
                        {}
                    }
                else
                    midware_arr[#midware_arr + 1] = {
                        v[1],
                        parse_config(v[2])
                    }
                end
            end
        end)
        return midware_arr
    elseif lw_util.is_array(midware_params) then
        local midware_arr = {}
        lw_util.foreach(midware_params, function(v)
            if lw_util.is_string(v) then
                map(function(m)
                    table.insert(midware_arr, m)
                end, manager.parse(v))
            elseif #v == 2 and lw_util.is_string(v[1]) and lw_util.is_array(v[2]) then
                table.insert(midware_arr, v)
            elseif #v == 1 and lw_util.is_string(v[1]) then
                map(function(m)
                    table.insert(midware_arr, m)
                end, manager.parse(v[1]))
            end
        end)
        return midware_arr
    end
    assert(false, 'params must be a string or two-values-table')
    return {}
end
return manager