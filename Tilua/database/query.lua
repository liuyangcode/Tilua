--- Tilua.database.query
--- SQL fragment builders (extracted from legacy driver)
--- Used by drivers and higher-level ORM.

local helpers = require("Tilua.core.helpers")
local lw_utils = require("Tilua.utils.util")

local Query = {}
Query.__index = Query

local EXP = {
    eq = "=", neq = "<>", gt = ">", egt = ">=", lt = "<", elt = "<=",
    notlike = "NOT LIKE", like = "LIKE",
    ["in"] = "IN", notin = "NOT IN", ["not in"] = "NOT IN",
    between = "BETWEEN", ["not between"] = "NOT BETWEEN", notbetween = "NOT BETWEEN",
}

local SELECT_SQL =
    "SELECT%DISTINCT% %FIELD% FROM %TABLE%%FORCE%%JOIN%%WHERE%%GROUP%%HAVING%%ORDER%%LIMIT% %UNION%%LOCK%%COMMENT%"

function Query.new(opts)
    local self = setmetatable({}, Query)
    self.escape = (opts and opts.escape) or function(s)
        if ngx and ngx.quote_sql_str then
            local q = ngx.quote_sql_str(tostring(s))
            if q:sub(1, 1) == "'" then
                return q:sub(2, -2)
            end
            return q
        end
        return lw_utils.addslashes and lw_utils.addslashes(tostring(s)) or tostring(s)
    end
    self.like_fields = opts and opts.like_fields
    return self
end

function Query:key(key)
    if key == nil then
        return ""
    end
    key = tostring(key)
    if key:find("[`%(]") then
        return key
    end
    local a, b = key:match("^([%w_]+)%.([%w_]+)$")
    if a and b then
        return "`" .. a .. "`.`" .. b .. "`"
    end
    if key:match("^[%w_]+$") then
        return "`" .. key .. "`"
    end
    return key
end

function Query:value(value)
    local t = type(value)
    if t == "string" then
        return "'" .. self.escape(value) .. "'"
    elseif t == "table" and type(value[1]) == "string" and string.lower(value[1]) == "exp" then
        return tostring(value[2])
    elseif t == "table" then
        local arr = {}
        for i, v in ipairs(value) do
            arr[i] = self:value(v)
        end
        return arr
    elseif t == "boolean" then
        return value and "1" or "0"
    elseif t == "nil" then
        return "NULL"
    elseif t == "number" then
        return tostring(value)
    end
    return "'" .. self.escape(tostring(value)) .. "'"
end

function Query:field(fields)
    if type(fields) == "string" and fields ~= "" then
        fields = helpers.split(fields, ",", true)
    end
    if type(fields) ~= "table" then
        return "*"
    end
    local array = {}
    for key, field in pairs(fields) do
        if type(key) == "string" and not tonumber(key) then
            array[#array + 1] = self:key(key) .. " AS " .. self:key(field)
        else
            array[#array + 1] = self:key(field)
        end
    end
    return #array > 0 and table.concat(array, ",") or "*"
end

function Query:table_name(tables)
    if type(tables) == "table" then
        local array = {}
        for alias, stable in pairs(tables) do
            if type(stable) == "number" then
                array[#array + 1] = self:key(alias)
            else
                array[#array + 1] = self:key(stable) .. " " .. self:key(alias)
            end
        end
        return table.concat(array, ",")
    end
    if type(tables) == "string" then
        local parts = helpers.split(tables, ",", true)
        for i, p in ipairs(parts) do
            parts[i] = self:key(helpers.strip(p))
        end
        return table.concat(parts, ",")
    end
    return tostring(tables or "")
end

function Query:where_item(key, val)
    local whereStr = ""
    if type(val) == "table" and type(val[1]) == "string" then
        local exp = string.lower(val[1])
        if EXP[exp] and (exp == "eq" or exp == "neq" or exp == "gt" or exp == "egt" or exp == "lt" or exp == "elt") then
            whereStr = key .. " " .. EXP[exp] .. " " .. self:value(val[2])
        elseif exp == "like" or exp == "notlike" then
            whereStr = key .. " " .. EXP[exp] .. " " .. self:value(val[2])
        elseif exp == "exp" then
            whereStr = key .. " " .. tostring(val[2])
        elseif exp == "in" or exp == "notin" or exp == "not in" then
            local list = val[2]
            if type(list) == "string" then
                list = helpers.split(list, ",", true)
            end
            local zone = table.concat(self:value(list), ",")
            whereStr = key .. " " .. EXP[exp] .. " (" .. zone .. ")"
        elseif exp == "between" or exp == "notbetween" or exp == "not between" then
            local data = type(val[2]) == "string" and helpers.split(val[2], ",", true) or val[2]
            whereStr = string.format("%s %s %s AND %s", key, EXP[exp], self:value(data[1]), self:value(data[2]))
        else
            error("where express err: " .. tostring(val[1]))
        end
    elseif type(val) == "table" then
        -- complex AND/OR list – simplified
        local parts = {}
        for i, item in ipairs(val) do
            if type(item) == "table" then
                parts[#parts + 1] = self:where_item(key, item)
            end
        end
        whereStr = "( " .. table.concat(parts, " AND ") .. " )"
    else
        if self.like_fields and self.like_fields == key then
            whereStr = key .. " LIKE " .. self:value("%" .. tostring(val) .. "%")
        else
            whereStr = key .. " = " .. self:value(val)
        end
    end
    return whereStr
end

function Query:where(where)
    if type(where) == "string" then
        return where == "" and "" or (" WHERE " .. where)
    end
    if type(where) ~= "table" or not next(where) then
        return ""
    end
    local operate = string.upper(tostring(where._logic or "AND"))
    if operate ~= "AND" and operate ~= "OR" and operate ~= "XOR" then
        operate = "AND"
    end
    where = helpers.deepcopy and helpers.deepcopy(where) or where
    where._logic = nil

    local parts = {}
    for key, val in pairs(where) do
        if type(key) == "number" then
            key = "_complex"
        end
        key = helpers.strip(tostring(key))
        parts[#parts + 1] = self:where_item(self:key(key), val)
    end
    if #parts == 0 then
        return ""
    end
    return " WHERE " .. table.concat(parts, " " .. operate .. " ")
end

function Query:order(order)
    if not order or order == "" then
        return ""
    end
    if type(order) == "string" then
        return " ORDER BY " .. order
    end
    if type(order) == "table" then
        local array = {}
        for key, val in pairs(order) do
            if type(key) == "number" then
                array[#array + 1] = tostring(val)
            else
                array[#array + 1] = self:key(key) .. " " .. string.upper(tostring(val))
            end
        end
        return " ORDER BY " .. table.concat(array, ",")
    end
    return ""
end

function Query:limit(limit)
    if not limit or limit == "" then
        return ""
    end
    return " LIMIT " .. tostring(limit) .. " "
end

function Query:set_clause(data)
    local set = {}
    for key, val in pairs(data or {}) do
        local t = type(val)
        if t == "table" and val[1] == "exp" then
            set[#set + 1] = self:key(key) .. "=" .. tostring(val[2])
        elseif val == "null" or val == nil then
            set[#set + 1] = self:key(key) .. "= NULL"
        else
            set[#set + 1] = self:key(key) .. "=" .. self:value(val)
        end
    end
    return " SET " .. table.concat(set, ",")
end

function Query:build_select(options)
    options = options or {}
    if options.page then
        local page = tonumber(options.page[1]) or 1
        local listRows = tonumber(options.page[2]) or 20
        if page < 1 then page = 1 end
        options.limit = ((page - 1) * listRows) .. " , " .. listRows
    end
    local express = {
        ["%TABLE%"] = self:table_name(options.table),
        ["%DISTINCT%"] = options.distinct and " DISTINCT " or "",
        ["%FIELD%"] = self:field(options.field or "*"),
        ["%JOIN%"] = type(options.join) == "table" and (" " .. table.concat(options.join, " ") .. " ") or (options.join or ""),
        ["%WHERE%"] = self:where(options.where or {}),
        ["%GROUP%"] = options.group and options.group ~= "" and (" GROUP BY " .. options.group) or "",
        ["%HAVING%"] = options.having and options.having ~= "" and (" HAVING " .. options.having) or "",
        ["%ORDER%"] = self:order(options.order),
        ["%LIMIT%"] = self:limit(options.limit),
        ["%UNION%"] = "",
        ["%LOCK%"] = options.lock and " FOR UPDATE " or "",
        ["%COMMENT%"] = options.comment and options.comment ~= "" and ("/*" .. options.comment .. "*/") or "",
        ["%FORCE%"] = "",
    }
    local function replace_all(s, old, newv)
        local i, out = 1, {}
        while true do
            local a, b = string.find(s, old, i, true)
            if not a then
                out[#out + 1] = string.sub(s, i)
                break
            end
            out[#out + 1] = string.sub(s, i, a - 1)
            out[#out + 1] = newv
            i = b + 1
        end
        return table.concat(out)
    end
    -- replace longer tokens first to avoid partial clashes (none currently)
    local order = {
        "%DISTINCT%", "%FIELD%", "%TABLE%", "%FORCE%", "%JOIN%",
        "%WHERE%", "%GROUP%", "%HAVING%", "%ORDER%", "%LIMIT%",
        "%UNION%", "%LOCK%", "%COMMENT%",
    }
    local sql = SELECT_SQL
    for _, exp in ipairs(order) do
        sql = replace_all(sql, exp, express[exp] or "")
    end
    return sql
end

function Query:build_insert(table_name, data, replace)
    local fields, values = {}, {}
    for key, val in pairs(data or {}) do
        fields[#fields + 1] = self:key(key)
        if type(val) == "table" and val[1] == "exp" then
            values[#values + 1] = tostring(val[2])
        elseif val == nil then
            values[#values + 1] = "NULL"
        else
            values[#values + 1] = self:value(val)
        end
    end
    local verb = replace and "REPLACE" or "INSERT"
    return verb .. " INTO " .. self:table_name(table_name) ..
        " (" .. table.concat(fields, ",") .. ") VALUES (" .. table.concat(values, ",") .. ")"
end

function Query:build_update(table_name, data, options)
    options = options or {}
    return "UPDATE " .. self:table_name(table_name) .. self:set_clause(data) ..
        self:where(options.where or {}) .. self:order(options.order) .. self:limit(options.limit)
end

function Query:build_delete(table_name, options)
    options = options or {}
    return "DELETE FROM " .. self:table_name(table_name) ..
        self:where(options.where or {}) .. self:order(options.order) .. self:limit(options.limit)
end

--- Bind ? placeholders
function Query:bind(sql, params)
    params = params or {}
    local i = 0
    return tostring(sql):gsub("%?", function()
        i = i + 1
        local v = params[i]
        if v == nil then
            return "NULL"
        end
        return self:value(v)
    end)
end


--- Fluent query builder for services / raw usage
---   Query.builder(db):table("users"):where({id=1}):first()
function Query.builder(db)
    local b = {
        _db = db,
        _q = (db and db.query) or Query.new({}),
        _opts = { where = {}, field = "*", table = nil },
    }
    function b:table(name)
        self._opts.table = name
        return self
    end
    function b:select(fields)
        self._opts.field = fields or "*"
        return self
    end
    function b:where(w)
        if type(w) == "table" then
            for k, v in pairs(w) do
                self._opts.where[k] = v
            end
        elseif type(w) == "string" then
            self._opts.where = w
        end
        return self
    end
    function b:order(o)
        self._opts.order = o
        return self
    end
    function b:limit(n)
        self._opts.limit = n
        return self
    end
    function b:page(p, size)
        self._opts.page = { p, size }
        return self
    end
    function b:lock(v)
        self._opts.lock = v and true or false
        return self
    end
    function b:sql()
        return self._q:build_select(self._opts)
    end
    function b:get()
        if not self._db then
            return nil, "no db"
        end
        return self._db:select(self._opts)
    end
    function b:first()
        self._opts.limit = 1
        local rows = self:get()
        if type(rows) == "table" then
            return rows[1]
        end
        return rows
    end
    function b:count()
        local opts = {}
        for k, v in pairs(self._opts) do opts[k] = v end
        opts.field = "COUNT(*) AS `aggregate`"
        opts.order = nil
        opts.limit = nil
        opts.page = nil
        local rows = self._db:select(opts)
        if type(rows) == "table" and rows[1] then
            return tonumber(rows[1].aggregate or rows[1]["COUNT(*)"])
        end
        return 0
    end
    return b
end

return Query
