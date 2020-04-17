
local ngx = ngx
local midware_sep = "|"
local midware_group = {}
local midware_group_parsed = {}
local lw_util = require('Tilua.util')
local map = require("pl.tablex").map
local split = require('pl.utils').split
local match = ngx.re.match

local manager = {}
function manager.is_group(val)
    local mat, _ = match(val, '[[a-zA-Z_0-9]+]')
    return mat ~= nil
end
function manager.init_group(group)
    midware_group = group
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
                    table.insert(midware_arr,m)
                end,manager.get_group(v))
            else
                v = split(v, ':')
                if #v == 1 then
                    midware_arr[#midware_arr +1 ] = {
                        v[1],
                        {}
                    }
                else
                    midware_arr[#midware_arr +1 ] = {
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
                    table.insert(midware_arr,m)
                end,manager.parse(v))
            elseif #v == 2 and lw_util.is_string(v[1]) and lw_util.is_array(v[2]) then
                table.insert(midware_arr,v)
            elseif #v == 1 and lw_util.is_string(v[1]) then
                map(function(m)
                    table.insert(midware_arr,m)
                end,manager.parse(v[1]))
            end
        end)
        return midware_arr
    end
    assert(false, 'params must be a string or two-values-table')
    return {}
end

return manager