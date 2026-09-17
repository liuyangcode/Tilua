--- Tilua.core.helpers
--- Lightweight pure-Lua helpers shared across the framework.
---
--- This module is the single home for the small table/string utilities the
--- framework needs.  It replaces Penlight (`pl.tablex` / `pl.pretty`), which is
--- not installed in a stock OpenResty — see `M.update` / `M.size` / `M.foreach` /
--- `M.pretty` for the former Penlight surface.

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

--- Penlight `tablex.update(dst, src)`: merge `src` into `dst` in place.
---
--- Array values are APPENDED rather than replaced:
---   update({1,2}, {3,4})            -> {1,2,3,4}
---   update({a={1,2}}, {a={3}})      -> {a={1,2,3}}
--- Everything else overwrites.
---
--- The array case MUST be detected on the source *table itself*, before
--- iterating it.  `pairs({3,4})` yields `1 -> 3, 2 -> 4`, so a per-element
--- `type(v) == "table"` test is false for every entry and the values silently
--- overwrite `dst[1]`/`dst[2]` instead of being appended.  That is the bug this
--- function shipped with twice.
---
--- Deliberately separate from `extend`, which is a flat overwrite used for
--- config merging — making `extend` append would duplicate middleware lists.
function M.update(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end

    -- Whole-source array: append it, never index-by-index.
    if M.is_array(src) then
        for i = 1, #src do
            dst[#dst + 1] = src[i]
        end
        return dst
    end

    for k, v in pairs(src) do
        local existing = dst[k]
        if type(v) == "table" then
            if type(existing) == "table" then
                M.update(existing, v)   -- recurse (handles nested arrays)
            else
                dst[k] = v
            end
        else
            dst[k] = v
        end
    end
    return dst
end

--- Count entries in a table (both array and hash part).
function M.size(t)
    if type(t) ~= "table" then
        return 0
    end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

--- Iterate any table in key order, calling `fn(value, key, ...)`.
--- Penlight calls this `tablex.foreach`; the argument order matches it.
function M.foreach(t, fn, ...)
    if type(t) ~= "table" or type(fn) ~= "function" then
        return
    end
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            if ta == "number" or ta == "string" then
                return a < b
            end
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    for i = 1, #keys do
        local k = keys[i]
        fn(t[k], k, ...)
    end
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

--- Render a value as readable, Lua-parseable text.
---
--- Pure-Lua stand-in for Penlight's `pretty.write` (used by `util.dump`).
--- Table keys are sorted so the output is stable across runs, and cycles are
--- reported instead of recursing forever.
local function format_key(k)
    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        return k
    end
    return "[" .. M.pretty(k) .. "]"
end

function M.pretty(value, indent, seen)
    indent = indent or 0
    local t = type(value)

    if t ~= "table" then
        if t == "string" then
            return string.format("%q", value)
        end
        return tostring(value)
    end

    seen = seen or {}
    if seen[value] then
        return "<cycle>"
    end
    seen[value] = true

    local pad = string.rep("  ", indent + 1)
    local close_pad = string.rep("  ", indent)

    -- array part first, in order
    local parts = {}
    for i = 1, #value do
        parts[#parts + 1] = pad .. M.pretty(value[i], indent + 1, seen)
    end
    -- then the remaining keys, sorted for stability
    local keys = {}
    for k in pairs(value) do
        if not (type(k) == "number" and k >= 1 and k <= #value and k == math.floor(k)) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            return tostring(a) < tostring(b)
        end
        return type(a) < type(b)
    end)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = pad .. format_key(k) .. " = "
            .. M.pretty(value[k], indent + 1, seen)
    end

    seen[value] = nil

    if #parts == 0 then
        return "{}"
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. close_pad .. "}"
end

return M

