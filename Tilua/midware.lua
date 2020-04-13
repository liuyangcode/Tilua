local class = require('pl.class')
local lw_util = require('Tilua.util')
local split = require('pl.utils').split
local match = ngx.re.match
local midware_sep = "|"
local midware_group = {}
local midware_group_parsed = {}
local midware = class()
function midware:_init(app)
    self.app = app
end

function midware:hanlde(...)
    assert(false, 'midware is base class ,cannot be instanced')
end
function midware.is_group(val)
    local mat,_ = match(val, '\\[[a-zA-Z_0-9]+\\]')
    return mat ~= nil
end
function midware.parse_group(val)
    if not midware.is_group(val) then
        return val
    end


end
---parse_midware_from_string
---@param midware_params string
---@return table
function midware.parse_midware_from_string(midware_params)
    if not midware_params then
        return {}
    end
    if lw_util.is_string(midware_params) then

        local midware_arr = split(midware_params, midware_sep)
        --lw_util.foreach(midware_arr, function(v)
        --
        --end)
        --map(midware.parse_midware, midware_arr)
        return midware_arr
    end
    assert(false, 'params must be a string')
    return {}
end
function midware.derive()
    return class(midware)
end

return midware