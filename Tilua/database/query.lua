local Query = {}
Query.__index = Query

local function quote_identifier(name)
    if type(name) ~= "string" or name == "" then error("invalid_sql_identifier") end
    if name == "*" then return name end
    local parts = {}
    for part in name:gmatch("[^%.]+") do
        if not part:match("^[%w_]+$") then error("invalid_sql_identifier: " .. tostring(name)) end
        parts[#parts + 1] = "`" .. part .. "`"
    end
    return table.concat(parts, ".")
end

local function value_sql(value)
    if value == nil then return "NULL" end
    if type(value) == "boolean" then return value and "1" or "0" end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge then error("invalid_sql_number") end
        return tostring(value)
    end
    if type(value) == "string" then return "'" .. value:gsub("\\", "\\\\"):gsub("'", "''") .. "'" end
    error("unsupported_sql_value: " .. type(value))
end

local operators = {
    eq = "=", neq = "<>", gt = ">", egt = ">=", lt = "<", elt = "<=",
    like = "LIKE", notlike = "NOT LIKE", ["in"] = "IN", notin = "NOT IN",
    ["not in"] = "NOT IN", between = "BETWEEN", ["not between"] = "NOT BETWEEN",
}

local function condition(key, value)
    local identifier = quote_identifier(key)
    if type(value) == "table" and value[1] then
        local op = string.lower(tostring(value[1]))
        local rhs = value[2]
        if op == "exp" then return identifier .. " " .. tostring(rhs) end
        local sql_op = operators[op]
        if not sql_op then error("unsupported_where_operator: " .. tostring(value[1])) end
        if op == "in" or op == "notin" or op == "not in" then
            if type(rhs) ~= "table" then error("where_in_requires_table") end
            local values = {}
            for _, item in ipairs(rhs) do values[#values + 1] = value_sql(item) end
            if #values == 0 then return op == "in" and "1=0" or "1=1" end
            return identifier .. " " .. sql_op .. " (" .. table.concat(values, ", ") .. ")"
        end
        if op == "between" or op == "not between" then
            if type(rhs) ~= "table" or #rhs < 2 then error("where_between_requires_two_values") end
            return identifier .. " " .. sql_op .. " " .. value_sql(rhs[1]) .. " AND " .. value_sql(rhs[2])
        end
        return identifier .. " " .. sql_op .. " " .. value_sql(rhs)
    end
    if value == nil then return identifier .. " IS NULL" end
    return identifier .. " = " .. value_sql(value)
end

local function where_sql(where, logic)
    if not where then return "" end
    if type(where) == "string" then return where ~= "" and " WHERE " .. where or "" end
    local parts = {}
    for key, value in pairs(where) do
        if key ~= "_logic" then parts[#parts + 1] = condition(key, value) end
    end
    if #parts == 0 then return "" end
    logic = string.upper(logic or where._logic or "AND")
    if logic ~= "AND" and logic ~= "OR" then error("invalid_where_logic") end
    return " WHERE " .. table.concat(parts, " " .. logic .. " ")
end

local function fields_sql(fields)
    if not fields or fields == "" then return "*" end
    if type(fields) == "string" then
        if fields == "*" then return fields end
        local result = {}
        for item in fields:gmatch("[^,]+") do
            local field = item:gsub("^%s+", ""):gsub("%s+$", "")
            local name, alias = field:match("^([%w_%.]+)%s+[Aa][Ss]%s+([%w_]+)$")
            if name then result[#result + 1] = quote_identifier(name) .. " AS " .. quote_identifier(alias)
            elseif field:match("^[%w_%.]+$") then result[#result + 1] = quote_identifier(field)
            else error("invalid_sql_field: " .. field) end
        end
        return table.concat(result, ", ")
    end
    local result = {}
    for _, field in ipairs(fields) do result[#result + 1] = quote_identifier(field) end
    return table.concat(result, ", ")
end

function Query.new(connection, table_name)
    return setmetatable({ connection = connection, _table = table_name, _fields = nil, _where = nil, _where_logic = nil, _order = nil, _group = nil, _having = nil, _limit = nil, _offset = nil, _distinct = false, _joins = {} }, Query)
end
function Query:table(name) self._table = name; return self end
function Query:fields(fields) self._fields = fields; return self end
function Query:select_fields(fields) return self:fields(fields) end
function Query:where(where, logic) self._where = where; self._where_logic = logic; return self end
function Query:where_eq(key, value) return self:where({ [key] = value }) end
function Query:order(order) self._order = order; return self end
function Query:group(group) self._group = group; return self end
function Query:having(having) self._having = having; return self end
function Query:limit(limit, offset) self._limit = limit; self._offset = offset; return self end
function Query:distinct(value) self._distinct = value ~= false; return self end
function Query:join(table_name, on, kind) self._joins[#self._joins + 1] = { table = table_name, on = on, kind = string.upper(kind or "INNER") }; return self end
function Query:left_join(table_name, on) return self:join(table_name, on, "LEFT") end
function Query:right_join(table_name, on) return self:join(table_name, on, "RIGHT") end

function Query:build_select(options)
    options = options or {}
    local table_name = options.table or self._table
    if not table_name then error("query_table_required") end
    local sql = "SELECT " .. ((options.distinct or self._distinct) and "DISTINCT " or "") .. fields_sql(options.fields or self._fields) .. " FROM " .. quote_identifier(table_name)
    for _, join in ipairs(options.joins or self._joins) do
        local kind = string.upper(join.kind or "INNER")
        if kind ~= "INNER" and kind ~= "LEFT" and kind ~= "RIGHT" and kind ~= "FULL" then error("invalid_join_type") end
        if type(join.on) ~= "string" or join.on == "" then error("join_condition_required") end
        sql = sql .. " " .. kind .. " JOIN " .. quote_identifier(join.table) .. " ON " .. join.on
    end
    sql = sql .. where_sql(options.where or self._where, options.where_logic or self._where_logic)
    local group = options.group or self._group
    if group then sql = sql .. " GROUP BY " .. fields_sql(group) end
    local having = options.having or self._having
    if having then sql = sql .. " HAVING " .. (type(having) == "string" and having or where_sql(having):gsub("^ WHERE ", "")) end
    local order = options.order or self._order
    if order then
        local items = {}
        if type(order) == "string" then
            for item in order:gmatch("[^,]+") do
                local name, direction = item:match("^%s*([%w_%.]+)%s*([Aa][Ss][Cc]|[Dd][Ee][Ss][Cc])?%s*$")
                if not name then error("invalid_sql_order") end
                items[#items + 1] = quote_identifier(name) .. " " .. string.upper(direction or "ASC")
            end
        else
            for name, direction in pairs(order) do
                direction = string.upper(direction)
                if direction ~= "ASC" and direction ~= "DESC" then error("invalid_sql_order") end
                items[#items + 1] = quote_identifier(name) .. " " .. direction
            end
        end
        sql = sql .. " ORDER BY " .. table.concat(items, ", ")
    end
    local limit = options.limit or self._limit
    local offset = options.offset or self._offset
    if limit ~= nil then
        limit = tonumber(limit)
        if not limit or limit < 0 or limit % 1 ~= 0 then error("invalid_sql_limit") end
        sql = sql .. " LIMIT " .. tostring(limit)
        if offset ~= nil then
            offset = tonumber(offset)
            if not offset or offset < 0 or offset % 1 ~= 0 then error("invalid_sql_offset") end
            sql = sql .. " OFFSET " .. tostring(offset)
        end
    end
    return sql
end

function Query:build_insert(data, options)
    options = options or {}
    local table_name = options.table or self._table
    if not table_name then error("query_table_required") end
    if type(data) ~= "table" then error("insert_data_required") end
    local keys = {}
    for key in pairs(data) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 then error("insert_data_empty") end
    local columns, values = {}, {}
    for _, key in ipairs(keys) do columns[#columns + 1] = quote_identifier(key); values[#values + 1] = value_sql(data[key]) end
    return "INSERT INTO " .. quote_identifier(table_name) .. " (" .. table.concat(columns, ", ") .. ") VALUES (" .. table.concat(values, ", ") .. ")"
end

function Query:build_update(data, options)
    options = options or {}
    local table_name = options.table or self._table
    if not table_name then error("query_table_required") end
    if type(data) ~= "table" then error("update_data_required") end
    local keys = {}
    for key in pairs(data) do keys[#keys + 1] = key end
    table.sort(keys)
    if #keys == 0 then error("update_data_empty") end
    local set = {}
    for _, key in ipairs(keys) do set[#set + 1] = quote_identifier(key) .. " = " .. value_sql(data[key]) end
    return "UPDATE " .. quote_identifier(table_name) .. " SET " .. table.concat(set, ", ") .. where_sql(options.where or self._where, options.where_logic or self._where_logic)
end

function Query:build_delete(options)
    options = options or {}
    local table_name = options.table or self._table
    if not table_name then error("query_table_required") end
    return "DELETE FROM " .. quote_identifier(table_name) .. where_sql(options.where or self._where, options.where_logic or self._where_logic)
end

function Query:raw(sql, ...) return self.connection:query(sql, ...) end
function Query:select(options, ...) if type(options) == "string" then return self.connection:select(options, ...) end; return self.connection:select(self:build_select(options)) end
function Query:insert(data, options) return self.connection:execute(self:build_insert(data, options)) end
function Query:update(data, options) return self.connection:execute(self:build_update(data, options)) end
function Query:delete(options) return self.connection:execute(self:build_delete(options)) end
function Query:to_sql(options) return self:build_select(options) end

return setmetatable(Query, { __call = function(_, ...) return Query.new(...) end })
