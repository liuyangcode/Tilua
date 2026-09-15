--- Tilua.core.helpers
--- Lightweight pure-Lua helpers to reduce Penlight dependency on hot paths.

local M = {}

--- Split string by separator (plain or pattern)
---@param str string
---@param sep string
---@param plain boolean|nil
---@return table
function M.split(str, sep, plain)
    if str == nil or str == "" then
        return {}
    end
    sep = sep or "%s+"
    plain = plain == true
    local t = {}
    local from = 1
    local delim_from, delim_to = string.find(str, sep, from, plain)
    while delim_from do
        t[#t + 1] = string.sub(str, from, delim_from - 1)
        from = delim_to + 1
        delim_from, delim_to = string.find(str, sep, from, plain)
    end
    t[#t + 1] = string.sub(str, from)
    return t
end

--- Strip whitespace from both ends
---@param s string
---@return string
function M.strip(s)
    if type(s) ~= "string" then
        return s
    end
    return (s:match("^%s*(.-)%s*$"))
end

--- Reverse array table (returns new table)
---@param t table
---@return table
function M.reverse(t)
    local n = #t
    local r = {}
    for i = 1, n do
        r[i] = t[n - i + 1]
    end
    return r
end

--- Simple map
---@param fn function
---@param t table
---@return table
function M.map(fn, t)
    local r = {}
    for i, v in ipairs(t) do
        r[i] = fn(v, i)
    end
    return r
end

--- Check if value is a non-empty array-like table
function M.is_array(t)
    if type(t) ~= "table" then
        return false
    end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            return false
        end
        if k > n then
            n = k
        end
    end
    return n == #t
end

function M.is_string(v)
    return type(v) == "string"
end

function M.empty(v)
    if v == nil then
        return true
    end
    local tv = type(v)
    if tv == "string" then
        return v == ""
    end
    if tv == "table" then
        return next(v) == nil
    end
    return false
end

--- Bind first argument (pure Lua)
function M.bind1(fn, p)
    return function(...)
        return fn(p, ...)
    end
end

--- Reduce array from left
function M.reduce(fn, list, init)
    local acc = init
    local start = 1
    if acc == nil and #list > 0 then
        acc = list[1]
        start = 2
    end
    for i = start, #list do
        acc = fn(acc, list[i], i)
    end
    return acc
end

--- Deep-ish extend (shallow for nested tables is enough for config)
function M.extend(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for k, v in pairs(src) do
        dst[k] = v
    end
    return dst
end

--- Find value in array; returns index or nil
function M.find(t, value)
    if type(t) ~= "table" then
        return nil
    end
    for i, v in ipairs(t) do
        if v == value then
            return i
        end
    end
    return nil
end

--- Array slice (1-based, inclusive end like pl.tablex.sub)
function M.sub(t, i, j)
    i = i or 1
    j = j or #t
    local r = {}
    for k = i, j do
        r[#r + 1] = t[k]
    end
    return r
end

--- Append values from src array into dst
function M.insertvalues(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end
    for _, v in ipairs(src) do
        dst[#dst + 1] = v
    end
    return dst
end

--- Shallow copy of array/hash table
function M.copy(t)
    if type(t) ~= "table" then
        return t
    end
    local r = {}
    for k, v in pairs(t) do
        r[k] = v
    end
    return r
end

--- Deep copy (tables only; no metatable / cycles)
function M.deepcopy(t, seen)
    if type(t) ~= "table" then
        return t
    end
    seen = seen or {}
    if seen[t] then
        return seen[t]
    end
    local r = {}
    seen[t] = r
    for k, v in pairs(t) do
        r[M.deepcopy(k, seen)] = M.deepcopy(v, seen)
    end
    return r
end

--- Map over array values (trim helper for request body)
function M.imap(fn, t)
    local r = {}
    for i, v in ipairs(t) do
        r[i] = fn(v, i)
    end
    return r
end

return M

