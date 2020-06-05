local class = require('pl.class')
local pl_utils = require "pl.utils"
local stringx = require "pl.stringx"
local tablex = require "pl.tablex"
local table_concat = table.concat
local string_find = string.find
local lw_utils = require("Tilua.util")
local choose = lw_utils.choose
local empty = lw_utils.empty
local is_array = lw_utils.is_array
local is_string = lw_utils.is_string
local is_number = lw_utils.is_number
local is_scalar = lw_utils.is_scalar
local foreach = lw_utils.foreach
local in_array = lw_utils.in_array
---@class driver
local driver = class()

function driver:properties()
    -- 当前操作所属的模型名
    self.model = nil
    -- 当前SQL指令
    self.queryStr = ''
    self.modelSql = {}
    -- 最后插入ID
    self.lastInsID = nil
    -- 返回或者影响记录数
    self.numRows = 0
    -- 事务指令数
    self.transTimes = 0
    -- 错误信息
    self.error = ''
    -- 数据库连接ID 支持多个连接
    self.linkID = {}
    -- 当前连接ID
    self._linkID = nil
    -- 数据库连接参数配置
    self.config = {
        type = '', -- 数据库类型
        hostname = '127.0.0.1', -- 服务器地址
        database = '', -- 数据库名
        username = '', -- 用户名
        password = '', -- 密码
        hostport = '', -- 端口
        dsn = '', --
        params = {}, -- 数据库连接参数
        charset = 'utf8', -- 数据库编码默认采用utf8
        prefix = '', -- 数据库表前缀
        debug = false, -- 数据库调试模式
        deploy = 0, -- 数据库部署方式:0 集中式(单一服务器),1 分布式(主从服务器)
        rw_separate = false, -- 数据库读写是否分离 主从式有效
        master_num = 1, -- 读写分离后 主服务器数量
        slave_no = '', -- 指定从服务器序号
        db_like_fields = '',
    }
    -- 数据库表达式
    self.exp = {
        eq = '=', neq = '<>', gt = '>',
        egt = '>=', lt = '<', elt = '<=',
        notlike = 'NOT LIKE', like = 'LIKE',
        ['in'] = 'IN', notin = 'NOT IN',
        ['not in'] = 'NOT IN', between = 'BETWEEN',
        ['not between'] = 'NOT BETWEEN',
        notbetween = 'NOT BETWEEN'
    }
    -- 查询表达式
    self.selectSql = 'SELECT%DISTINCT% %FIELD% FROM %TABLE%%FORCE%%JOIN%%WHERE%%GROUP%%HAVING%%ORDER%%LIMIT% %UNION%%LOCK%%COMMENT%'
    -- 查询次数
    self.queryTimes = 0
    -- 执行次数
    self.executeTimes = 0
end

function driver:_init(config, context, logger)
    self:properties()
    if config then
        tablex.update(self.config, config)
    end
    self.logger = logger
    self.ctx = context
end

function driver.derive()
    return class(driver)
end
function driver:connect(config, linkNum, autoConnection)
    --todo
end
function driver:parseDsn(config)

end

function driver:query(str, fetchSql, master)
    self:initConnect(master)
    if not self._linkID then
        return false
    end
    self.queryStr = str

    if fetchSql then
        return self.queryStr
    end

    self.queryTimes = self.queryTimes + 1
    self:debug(true)
    self:execute_sql(str)
    self:debug(false)
    return self:getResult()
end

function driver:execute(str, fetchSql)
    self:initConnect(true)

    if not self._linkID then
        return false
    end
    self.queryStr = str
    if self.model then
        self.modelSql[self.model] = str
    end
    if fetchSql then
        return self.queryStr
    end
    --todo
    self.executeTimes = self.executeTimes + 1
    self:debug(true)
    self:execute_sql(str)
    self:debug(false)
    return self:getResult()
end

---启动事务
function driver:startTrans()
    self:initConnect(true)
    if not self._linkID then
        return false
    end
    if 0 == self.transTimes then
        self.transPdo = self._linkID
        self._linkID:beginTransaction()
    end
    self.transTimes = self.transTimes + 1
    return
end

---用于非自动提交状态下面的查询提交
function driver:commit()
    if 1 == self.transTimes then
        local result = self._linkID:commit()
        self.transTimes = 0
        self.transPdo = nil
        if not result then
            self:error()
            return false
        end
    else
        self.transTimes = choose(self.transTimes <= 0, 0, self.transTimes - 1)
    end
    return true
end

---事务回滚
function driver:rollback()
    if self.transTimes > 0 then
        local result = self._linkID:rollback()
        self.transTimes = 0
        if not result then
            self:error()
            return false
        end
    end
    return true
end

---获得所有的查询数据
function driver:getResult()
    self.numRows = #self.result_sets
    return self.result_sets
end

---获得查询次数
---@param execute boolean
function driver:getQueryTimes(execute)
    return choose(execute, self.queryTimes + self.executeTimes, self.queryTimes)
end

---获得执行次数
function driver:getExecuteTimes()
    return self.executeTimes
end

---关闭数据库
function driver:close()

end

---error
function driver:error()
    --todo
end

---设置锁机制
---@param lock boolean
function driver:parseLock(lock)
    return choose(lock, ' FOR UPDATE ', '')
end

---set分析
---@param data table
function driver:parseSet(data)
    local set = {}
    local this = self
    foreach(data, function(val, key)
        if val[1] and 'exp' == val[1] then
            set[#set + 1] = this:parseKey(key) .. '=' .. val[2]
        elseif val == 'null' then
            set[#set + 1] = this:parseKey(key) .. '= NULL'
        elseif is_scalar(val) then
            set[#set + 1] = this:parseKey(key) .. '=' .. self:parseValue(val)
        end
    end)
    return ' SET ' .. table_concat(set, ',')
end

---字段和表名处理
---@param key string
---@param strict boolean
function driver:parseKey(key, strict)
    return key
end

---value分析
---@param value any
function driver:parseValue(value)
    if is_string(value) then
        value = '\'' .. self:escapeString(value) .. '\''
    elseif is_array(value) and is_string(value[1]) and string.lower(value[1]) == 'exp' then
        value = self:escapeString(value[2])
    elseif type(value) == 'table' then
        value = tablex.map(pl_utils.bind1(self.parseValue, self), value)
    elseif type(value) == 'boolean' then
        value = choose(value, '1', '0')
    elseif type(value) == 'nil' then
        value = 'null'
    end
    return value
end

---field分析
---@param fields any
function driver:parseField(fields)
    if type(fields) == 'string' and '' ~= fields then
        fields = stringx.split(fields, ',')
    end
    local fieldsStr
    if type(fields) == 'table' then
        local array = {}
        foreach(fields, function(field, key)
            if not is_number(key) then
                array[#array + 1] = self:parseKey(key) .. ' AS ' .. self:parseKey(field)
            else
                array[#array + 1] = self:parseKey(field)
            end
        end)
        fieldsStr = table_concat(array, ',')
    else
        fieldsStr = '*'
    end
    return fieldsStr
end

---table分析
---@param tables any
function driver:parseTable(tables)
    if is_array(tables) then
        local array = {}
        foreach(tables, function(alias, stable)
            if type(stable) ~= 'number' then
                array[#array + 1] = self:parseKey(stable) .. '  ' .. self:parseKey(alias)
            else
                array[#array + 1] = self:parseKey(alias)
            end
        end)
        tables = array
    elseif type(tables) == 'string' then
        tables = tablex.map(pl_utils.bind1(self.parseKey), stringx.split(tables, ','))
    end
    return table_concat(tables, ',')
end

function driver:parseWhere(where)

    local whereStr = ""
    if lw_utils.is_string(where) then
        whereStr = where
    else
        local operate = string.upper(where._logic or '')
        if in_array({ 'AND', 'OR', 'XOR' }, operate) then
            operate = ' ' .. operate .. ' '
            where._logic = nil
        else
            operate = ' AND '
        end
        foreach(where, function(val, key)
            if is_number(key) then
                key = '_complex'
            end
            local multi = type(val) == 'table' and val._multi
            key = stringx.strip(key)
            if string_find(key, '|') then
                local array = stringx.split(key, '|')
                local str = {}
                foreach(array, function(k, m)
                    local v = choose(multi, val[m], val)
                    str[#str + 1] = '(' .. self:parseWhereItem(self:parseKey(k), v)
                end)
                whereStr = table_concat({
                    whereStr,
                    '（ ',
                    table_concat(str, ' OR '),
                    ')'
                })
            elseif string_find(key, '&') then
                local array = stringx.split(key, '&')
                local str = {}
                foreach(array, function(k, m)
                    local v = choose(multi, val[m], val)
                    str[#str + 1] = '(' .. self:parseWhereItem(self:parseKey(k), v)
                end)
                whereStr = table_concat({
                    whereStr,
                    '（ ',
                    table_concat(str, ' AND '),
                    ')'
                })
            else
                whereStr = table_concat({
                    whereStr,
                    self:parseWhereItem(self:parseKey(key), val)
                })
            end
            whereStr = whereStr .. operate
        end)
        whereStr = string.sub(whereStr, 1, -#operate)
    end
    return choose('' == whereStr, '', ' WHERE ' .. whereStr)
end
---where子单元分析
---@param key any
---@param val any
function driver:parseWhereItem(key, val)
    local whereStr = ''
    if is_array(val) then
        if is_string(val[1]) then
            local exp = string.lower(val[1])
            if tablex.find({ 'eq', 'neq', 'gt', 'egt', 'lt', 'elt' }, exp) then
                whereStr = table_concat({
                    whereStr,
                    key,
                    ' ',
                    self.exp[exp],
                    ' ',
                    self:parseValue(val[2])
                })
            elseif tablex.find({ 'notlike', 'like' }, exp) then
                if type(val[2]) == 'table' then
                    local likeLogic = choose(val[3], string.lower(val[3]), 'OR')
                    if likeLogic == 'AND' or likeLogic == 'OR' or likeLogic == 'XOR' then
                        local like = {}
                        foreach(val[2], function(item)
                            like[#like + 1] = table_concat({
                                key,
                                ' ',
                                self.exp[exp],
                                ' ',
                                self:parseValue(val[2])
                            })
                        end)
                        whereStr = table_concat({
                            whereStr,
                            '(',
                            table_concat(like, ' ' .. likeLogic .. ' '),
                            ')'
                        })
                    end
                else
                    --                        $whereStr .= $key . ' ' . $this->exp[$exp] . ' ' . $this->parseValue($val[1]);
                    whereStr = table_concat({
                        whereStr,
                        key,
                        ' ',
                        self.exp[exp],
                        ' ',
                        self:parseValue(val[2])

                    })
                end
            elseif 'exp' == exp then
                whereStr = whereStr .. key .. ' ' .. val[2]
            elseif exp == 'notin' or exp == 'not in' or 'in' == exp then
                if val[3] and 'exp' == val[3] then
                    whereStr = whereStr .. key .. ' ' .. self.exp[exp] .. ' ' .. val[2]
                else
                    if type(val[2]) == 'string' then
                        val[1] = stringx.split(val[2], ',')
                    end
                    local zone = table_concat(self:parseValue(val[2]), ',')
                    whereStr = whereStr .. key .. ' ' .. self.exp[exp] .. ' (' .. zone .. ' )'
                end
            elseif exp == 'notbetween' or exp == 'not between' or exp == 'between' then
                local data = choose(type(val[2]) == 'string', stringx.split(val[2], ',', val[2]))
                whereStr = string.format('%s%s %s %s AND %s', whereStr, key, self.exp[exp], self:parseValue(data[1]), self:parseValue(data[2]))
            else
                error('where express err' .. val[1])
            end
        else
            local count = #val
            local rule = ""
            if val[count] then
                rule = string.upper(val[count][1] or val[count])
            end
            if rule == 'AND' or rule == 'OR' or 'XOR' then
                count = count - 1
            else
                rule = 'AND'
            end
            for i = 1, count do
                local data = choose(type(val[i]) == 'table', val[i][2], val[i])
                if 'exp' == string.lower(val[i][1]) then
                    whereStr = whereStr .. key .. ' ' .. data .. ' ' .. rule .. ' '
                else
                    whereStr = whereStr .. self:parseWhereItem(key, val[i]) .. ' ' .. rule .. ' '
                end
            end
            whereStr = '( ' .. string.sub(whereStr, 1, -4) .. ' )'
        end
    else
        local likeFields = self.config.db_like_fields
        if likeFields and likeFields == key then
            whereStr = whereStr .. key .. ' LIKE ' .. self:parseValue('%' .. val .. '%')
        else
            whereStr = whereStr .. key .. ' = ' .. self:parseValue(val)
        end
    end
    return whereStr
end

function driver:parseLimit(limit)
    limit = limit or ''
    return choose(limit ~= '' and not string_find(limit, '\\('), ' LIMIT ' .. limit .. ' ', '')
end

function driver:parseJoin(join)
    local joinStr = ''
    if is_array(join) then
        joinStr = ' ' .. table_concat(join, ' ') .. ' '
    end
    return joinStr
end

function driver:parseOrder(order)
    if not order or order == '' then
        return ''
    end
    local array = {}
    if type(order) == 'string' and '[RAND]' ~= order then
        order = tablex.map(stringx.strip, stringx.split(order, ','))
    end
    if type(order) == 'table' then
        foreach(order, function(val, key)
            local sort
            if type(key) == 'number' then
                local tmp = stringx.split(choose(string_find(val, ' '), val, val .. ' '))
                key = tmp[1]
                sort = tmp[2]
            else
                sort = val
            end
            if ngx.re.match(key, '^[\\w\\.]+$') then
                sort = string.upper(sort)
                sort = choose(sort == 'ASC' or sort == 'DESC', ' ' .. sort, '')
                if string_find(key, '\\.') then
                    local tmp = stringx.split(key, '\\.')
                    local alias = tmp[1]
                    local key = tmp[2]
                    array[#array + 1] = self:parseKey(alias, true) .. '.' .. self:parseKey(key, true) .. sort
                else
                    array[#array + 1] = self:parseKey(key, true) .. sort
                end
            end
        end)
    elseif '[RAND]' == order then
        array[#array + 1] = self:parseRand()
    end
    order = table_concat(array, ',')
    return choose(order, ' ORDER BY ' .. order, '')
end
function driver:parseGroup(group)
    return choose(group and group ~= '', ' GROUP BY ' .. group, '')
end

function driver:parseHaving(having)
    return choose(having and having ~= '', ' HAVING ', '')
end
function driver:parseComment(comment)
    comment = comment or ''
    return choose(not empty(comment), '/*' .. comment .. '*/', '')
end
function driver:parseDistinct(distinct)
    return choose(distinct, ' DISTINCT ', '')
end

function driver:parseUnion(union)
    if not union or union == '' then
        return ''
    end
    local str
    if union._all then
        str = 'UNION ALL '
        union._all = nil
    else
        str = 'UNION '
    end
    local sql = {}
    foreach(union, function(u)
        sql[#sql + 1] = str .. choose(type(u) == 'table', self:buildSelectSql(u), u)
    end)
    return table_concat(sql, ' ')
end

function driver:parseForce(index)
    if not index or index == '' then
        return ''
    end
    if type(index) == 'table' then
        index = stringx.split(index, ',')
    end
    return string.format(' FORCE INDEX ( %s )', index)
end
function driver:parseDuplicate(duplicate)
    return ''
end
function driver:insert(data, options, replace)
    local values = {}
    local fields = {}
    self.model = options.model

    foreach(data, function(val, key)
        if type(val) == 'table' and 'exp' == val[1] then
            values[#values + 1] = val[2]
            fields[#fields + 1] = self:parseKey(key)
        elseif not val then
            values[#values + 1] = 'NULL'
            fields[#fields + 1] = self:parseKey(key)
        elseif is_scalar(val) then
            fields[#fields + 1] = self:parseKey(key)
            values[#values + 1] = self:parseValue(val)
        end
    end)
    replace = choose(is_number(replace) and replace > 0, true, replace)
    local sql = choose(replace, 'REPLACE', 'INSERT') .. ' INTO ' .. self:parseTable(options.table) .. ' (' .. table_concat(fields, ',') .. ') VALUES (' .. table_concat(values, ',') .. ' )' .. self:parseDuplicate(replace)
    sql = sql .. self:parseComment(options.comment or '')
    return self:execute(sql, options.fetch_sql)
end

function driver:insertAll(dataSet, options, replace)
    local values = {}
    self.model = options.model
    if type(dataSet[1]) ~= 'table' then
        return false
    end
    local fields = tablex.map(pl_utils.bind1(self.parseKey, self), tablex.keys(dataSet[1]))
    foreach(dataSet, function(data)
        local value = {}
        foreach(data, function(val, key)
            if type(val) == 'table' and 'exp' == val[1] then
                value[#value + 1] = val[2]
            elseif not val then
                value[#value + 1] = 'NULL'
            elseif is_scalar(val) then
                value[#value + 1] = self:parseValue(val)
            end
        end)
        values[#values + 1] = ' SELECT ' .. table_concat(value, ',')
    end)
    local sql = 'INSERT INTO ' .. self:parseTable(options.table) .. ' (' .. table_concat(fields, ',') .. ') ' .. table_concat(values, ' UNION ALL')
    sql = sql .. self:parseComment(options.comment or '')
    return self:execute(sql, options.fetch_sql)
end

function driver:selectInsert(fields, tableName, options)
    self.model = options.model
    if type(fields) == 'string' then
        fields = stringx.split(fields, ',')
    end
    fields = tablex.map(pl_utils.bind1(self.parseKey, self), fields)
    local sql = ' INSERT INTO ' .. self:parseTable(tableName) .. ' (' .. table_concat(fields, ',') .. ') '
    sql = sql .. self:buildSelectSql(options)
    return self:execute(sql, options.fetch_sql)
end

---删除记录
---@param options any
function driver:delete(options)
    options = options or {}
    self.model = options.model
    local tableName = self:parseTable(options.table)
    local sql = ' DELETE FROM ' .. tableName
    if string_find(tableName, ',') then
        if not empty(options.using) then
            sql = sql .. ' USING ' .. self:parseTable(options.using) .. ' '
        end
        sql = sql .. self:parseJoin(options.join)
    end
    sql = sql .. self:parseWhere(options.where)
    if not string_find(tableName, ',') then
        sql = sql .. self:parseOrder(options.order) .. self:parseLimit(options.limit)
    end
    sql = sql .. self:parseComment(options.comment)
    return self:execute(sql, options.fetch_sql)
end

function driver:update(data, options)
    self.model = options.model
    local tableName = self:parseTable(options.table)
    local sql = 'UPDATE ' .. tableName .. self:parseSet(data)

    if string_find(tableName, ',') then
        sql = sql .. self:parseJoin(options.join or '')
    end
    sql = sql .. self:parseWhere(options.where or '')
    if not string_find(tableName, ',') then
        sql = sql .. self:parseOrder(options.order or '') .. self:parseLimit(options.limit or '')
    end
    sql = sql .. self:parseComment(options.comment or '')
    return self:execute(sql, options.fetch_sql)
end

function driver:select(options)
    self.model = options.model
    local sql = self:buildSelectSql(options)
    return self:query(sql, options.fetch_sql, options.master)
end

function driver:buildSelectSql(options)
    if options.page then
        local page = options.page[1]
        local listRows = options.page[2]
        page = choose(page > 0, page, 1)
        listRows = choose(listRows > 0, listRows, choose(type(options.limit) == 'number'), options.limit, 20)
        local offset = listRows * (page - 1)
        options.limit = offset .. ' , ' .. listRows
    end
    return self:parseSql(self.selectSql, options)
end

---替换SQL语句中表达式
---@param sql string
---@param options table
function driver:parseSql(sql, options)
    local express = {
        ['%TABLE%'] = self:parseTable(options.table),
        ['%DISTINCT%'] = self:parseDistinct(options.distinct or false),
        ['%FIELD%'] = self:parseField(options.field or '*'),
        ['%JOIN%'] = self:parseJoin(options.join or ''),
        ['%WHERE%'] = self:parseWhere(options.where or ''),
        ['%GROUP%'] = self:parseGroup(options.group or ''),
        ['%HAVING%'] = self:parseHaving(options.having or ''),
        ['%ORDER%'] = self:parseOrder(options.order or ''),
        ['%LIMIT%'] = self:parseLimit(options.limit or ''),
        ['%UNION%'] = self:parseUnion(options.union or ''),
        ['%LOCK%'] = self:parseLock(options.lock or false),
        ['%COMMENT%'] = self:parseComment(options.comment or ''),
        ['%FORCE%'] = self:parseForce(options.force or '')
    }
    foreach(express, function(val, exp)
        sql = stringx.replace(sql, exp, val)
    end)
    return sql
end

function driver:setModel(model)
    self.model = model
end
---SQL指令安全过滤
---@param str string
function driver:escapeString(str)
    return lw_utils.addslashes(str)
end

function driver:getLastSql(model)
    return choose(not empty(model), self.modelSql[model], self.queryStr)
end

function driver:getError()
    return self.error
end
function driver:getLastInsID()
    return self.lastInsID
end
function driver:debug(start)
    if self.config.debug then
        if self.model then
            self.modelSql[self.model] = self.queryStr
        end
        if not start then
            self.logger:debug(self.queryStr, lw_utils.get_now_ms() - self.MYSQL_EXCUTE_SQL_START, ' ms')
        else
            self.MYSQL_EXCUTE_SQL_START = lw_utils.get_now_ms()
        end
    end
end
---初始化数据库连接
---@param master boolean
function driver:initConnect(master)
    master = master or true
    if self.config.deploy then
        self._linkID = self:multiConnect(master)
    else
        if not self._linkID then
            self._linkID = self:connect()
        end
    end
end

function driver:multiConnect(master)
    local _config = {
        username = stringx.split(self.config.username, ','),
        password = stringx.split(self.config.password, ','),

        hostname = stringx.split(self.config.hostname, ','),

        hostport = stringx.split(self.config.hostport, ','),

        database = stringx.split(self.config.database, ','),

        dsn = stringx.split(self.config.dsn, ','),
        charset = stringx.split(self.config.charset, ','),
    }
    local m = math.random(1, self.config.master_num)
    local r
    if self.config.rw_separate then
        if master then
            r = m
        else
            if type(self.config.slave_no) == 'number' then
                r = self.config.slave_no
            else
                r = math.random(self.config.master_num, #_config.hostname)
            end
        end
    else
        r = math.random(1, #_config.hostname)
    end
    local db_master
    if m ~= r then
        db_master = {
            username = _config.username[m] or _config.username[1],
            password = _config.password[m] or _config.password[1],
            hostname = _config.hostname[m] or _config.hostname[1],
            hostport = _config.hostport[m] or _config.hostport[1],
            database = _config.database[m] or _config.database[1],
            dsn = _config.dsn[m] or _config.dsn[1],
            charset = _config.charset[m] or _config.charset[1],
        }
    end
    local db_conig = {
        username = _config.username[r] or _config.username[1],
        password = _config.password[r] or _config.password[1],
        hostname = _config.hostname[r] or _config.hostname[1],
        hostport = _config.hostport[r] or _config.hostport[1],
        database = _config.database[r] or _config.database[1],
        dsn = _config.dsn[r] or _config.dsn[1],
        charset = _config.charset[r] or _config.charset[1],
    }
    return self:connect(db_conig, r, choose(r == m, false, db_master))
end

return driver