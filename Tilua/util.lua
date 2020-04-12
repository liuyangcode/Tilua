local tablex = require "pl.tablex"
local tablex_size = tablex.size
local foreach = tablex.foreach
local ngx = ngx
local md5 = ngx.md5
local json = require("cjson.safe")
---@class util
local util = {

}

---choose
---@param condition boolean
---@param value_true any
---@param value_false any
function util.choose(condition, value_true, value_false)
    if not not condition then
        return value_true
    end
    return value_false
end

function util.json_encode(data)
    return json.encode(data)
end
function util.json_decode(data)
    return json.decode(data)
end
function util.md5(str)
    return md5(str)
end
---is_array
---@param val any
function util.is_array(val)
    return type(val) == 'table'
end

local function pairsByKeys(t)
    local a = {}

    for n in pairs(t) do
        a[#a + 1] = n
    end

    table.sort(a)

    local i = 0

    return function()
        i = i + 1
        return a[i], t[a[i]]
    end
end

---extend
---@param dest table
---@param src table
function util.extend(dest, src)
    assert(util.is_array(src) and util.is_array(dest), 'util.extend second parametes must be table')
    for k, v in pairs(src) do
        if util.is_array(v) and util.is_array(dest[k]) then
            tablex.update(dest[k], v)
        else
            dest[k] = v
        end
    end
end

function util.foreach(t, func, ...)
    for k, v in pairsByKeys(t) do
        func(v, k, ...)
    end
end
function util.callable(f)
    if type(f) == "function" then
        return true
    end
    local m = getmetatable(f)
    return m and type(m.__call) == "function"
end
function util.dump(...)
    local params = { ... }
    for i = 1, #params do
        ngx.say(util.json_encode(params[i]) .. '<br/>')

    end
end

---check vals is nil
function util.is_set(...)
    local params = { ... }
    for i = 1, #params do
        if params[i] == nil then
            return false
        end
    end
    return true
end

---reverseTable
---@param tab table
---@return table
function util.reverseTable(tab)
    local tmp = {}
    for i = 1, #tab do
        tmp[i] = table.remove(tab)
    end
    return tmp
end

function util.is_string(val)
    return type(val) == 'string'
end

function util.is_scalar(val)
    return util.is_boolean(val) or util.is_string(val) or util.is_number(val)
end

---in_array
---@param array table
---@param val any
function util.in_array(array, val)
    return tablex.find(array, val) ~= nil
end

function util.is_number(val)
    return type(val) == 'number'
end

---序列化数组为字符串
---@param data table
function util.serialize(data)
    return util.json_encode(data)
end

function util.get_hash(data)
    return md5(util.serialize(data))
end
function util.is_boolean(val)
    return type(val) == 'boolean'
end
---判断值是否为空
---@param val any
function util.empty(val)
    if util.is_array(val) then
        return tablex_size(val) == 0
    elseif util.is_string(val) then
        return val == ''
    elseif type(val) == 'nil' then
        return true
    end
    return false
end

---判断所有传入的值是否有空
function util.emptys(...)
    local result = true
    local args = { ... }
    foreach(args, function(val)
        result = result and util.empty(val)
    end)
    return result
end
return util