--- Tilua.database.driver.mysql
--- MySQL driver implementing execute/query/schema on top of Connection + Query

local Connection = require("Tilua.database.connection")
local Query = require("Tilua.database.query")
local Transaction = require("Tilua.database.transaction")
local helpers = require("Tilua.core.helpers")

local Mysql = {}
Mysql.__index = Mysql

-- process-local schema cache
Mysql._fields_mem = Mysql._fields_mem or {}

function Mysql.new(config, ctx, logger)
    local self = setmetatable({}, Mysql)
    self.config = config or {}
    self.ctx = ctx
    self.logger = logger
    self.connection = Connection.new(self.config, logger)
    self.query = Query.new({
        like_fields = self.config.db_like_fields,
    })
    self.tx = Transaction.new(self)
    self.model = nil
    self.modelSql = {}
    self.queryStr = ""
    self.lastInsID = nil
    self.numRows = 0
    self.transTimes = 0
    self.result_sets = nil
    self.queryTimes = 0
    self.executeTimes = 0
    self.error = ""
    -- compat aliases used by legacy driver
    self.linkID = self.connection.link_id
    self._linkID = nil
    return self
end

function Mysql:initConnect(master)
    local sock, err = self.connection:connect_mysql(1)
    if not sock then
        self.error = err
        return nil
    end
    self._linkID = sock
    self.linkID = self.connection.link_id
    return sock
end

function Mysql:connect(config, linkNum)
    if config then
        for k, v in pairs(config) do
            self.config[k] = v
            self.connection.config[k] = v
        end
    end
    return self.connection:connect_mysql(linkNum or 1)
end

function Mysql:beginTransaction()
    self:initConnect(true)
    local res, err = self._linkID:query("START TRANSACTION")
    if not res then
        error(err or "START TRANSACTION failed")
    end
    return true
end

function Mysql:commitTrans()
    self:initConnect(true)
    local res, err = self._linkID:query("COMMIT")
    if not res then
        error(err or "COMMIT failed")
    end
    return true
end

function Mysql:rollback()
    if self._linkID then
        pcall(function()
            self._linkID:query("ROLLBACK")
        end)
    end
    self.transTimes = 0
    return true
end

function Mysql:startTrans()
    if self.transTimes == 0 then
        self:beginTransaction()
    end
    self.transTimes = self.transTimes + 1
end

function Mysql:commit()
    if self.transTimes == 1 then
        local r = self:commitTrans()
        self.transTimes = 0
        return r
    elseif self.transTimes > 1 then
        self.transTimes = self.transTimes - 1
    end
    return true
end

function Mysql:execute_sql(sql)
    if not self._linkID then
        self:initConnect(true)
    end
    if not self._linkID then
        return nil, "mysql not connected"
    end
    local res, err, errcode, sqlstate = self._linkID:query(sql)
    if not res then
        local msg = tostring(err) .. " errcode " .. tostring(errcode or "") .. " sqlstate:" .. tostring(sqlstate or "")
        if self.logger then
            self.logger:error(msg)
        end
        self.error = msg
        return nil, msg
    end
    if type(res) == "table" and res.insert_id then
        self.lastInsID = res.insert_id
        self.numRows = res.affected_rows or 0
        self.result_sets = res
        return res
    end
    self.numRows = type(res) == "table" and #res or 0
    self.result_sets = res
    return res
end

function Mysql:query(str, fetchSql, master)
    self:initConnect(master ~= false)
    self.queryStr = str
    if fetchSql then
        return str
    end
    self.queryTimes = self.queryTimes + 1
    return self:execute_sql(str)
end

function Mysql:execute(str, fetchSql)
    self:initConnect(true)
    self.queryStr = str
    if self.model then
        self.modelSql[self.model] = str
    end
    if fetchSql then
        return str
    end
    self.executeTimes = self.executeTimes + 1
    return self:execute_sql(str)
end

function Mysql:query_bind(sql, params, fetchSql, master)
    return self:query(self.query:bind(sql, params), fetchSql, master)
end

function Mysql:execute_bind(sql, params, fetchSql)
    return self:execute(self.query:bind(sql, params), fetchSql)
end

function Mysql:select(options)
    self.model = options.model
    local sql = self.query:build_select(options)
    return self:query(sql, options.fetch_sql, options.master)
end

function Mysql:insert(data, options, replace)
    options = options or {}
    self.model = options.model
    local sql = self.query:build_insert(options.table, data, replace)
    if options.comment then
        sql = sql .. " /*" .. options.comment .. "*/"
    end
    return self:execute(sql, options.fetch_sql)
end

function Mysql:update(data, options)
    options = options or {}
    self.model = options.model
    local sql = self.query:build_update(options.table, data, options)
    return self:execute(sql, options.fetch_sql)
end

function Mysql:delete(options)
    options = options or {}
    self.model = options.model
    local sql = self.query:build_delete(options.table, options)
    return self:execute(sql, options.fetch_sql)
end

function Mysql:getFields(tableName)
    local cache_key = tostring(self.config.database or "") .. ":" .. tostring(tableName)
    if Mysql._fields_mem[cache_key] then
        return Mysql._fields_mem[cache_key]
    end
    self:initConnect(true)
    local name = tostring(tableName):match("^%S+") or tableName
    local sql
    if name:find(".", 1, true) then
        local dbn, tn = name:match("^([^.]+)%.(.+)$")
        sql = "SHOW COLUMNS FROM `" .. dbn .. "`.`" .. tn .. "`"
    else
        sql = "SHOW COLUMNS FROM `" .. name .. "`"
    end
    local result, err = self:execute_sql(sql)
    if not result then
        error(err)
    end
    local info = {}
    for _, val in ipairs(result) do
        local row = {}
        for k, v in pairs(val) do
            row[string.lower(k)] = v
        end
        info[row.field] = {
            name = row.field,
            type = row.type,
            notnull = (row.null == "" or row.null == "NO"),
            default = row.default,
            primary = string.lower(row.key or "") == "pri",
            autoinc = string.lower(row.extra or "") == "auto_increment",
        }
    end
    Mysql._fields_mem[cache_key] = info
    return info
end

function Mysql:getResult()
    return self.result_sets
end

function Mysql:getLastSql(model)
    if model and self.modelSql[model] then
        return self.modelSql[model]
    end
    return self.queryStr
end

function Mysql:getLastInsID()
    return self.lastInsID
end

function Mysql:getError()
    return self.error
end

function Mysql:setModel(model)
    self.model = model
end

function Mysql:close()
    self.connection:close()
    self._linkID = nil
end

-- Compat: parse* delegated to Query for legacy model code paths
function Mysql:parseKey(k)
    return self.query:key(k)
end
function Mysql:parseValue(v)
    return self.query:value(v)
end
function Mysql:escapeString(s)
    return self.query.escape(s)
end
function Mysql:buildSelectSql(options)
    return self.query:build_select(options)
end

return Mysql
