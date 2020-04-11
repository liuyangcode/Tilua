
local stringx = require "pl.stringx"
local split = stringx.split
local strip = stringx.strip
local Db = require "Tilua.db"
local tablex = require "pl.tablex"
local class = require "pl.class"
local md5 = ngx.md5
local json = require "cjson.safe"
local now = ngx.now
local pl_utils = require "pl.utils"
local lw_utils = require("Tilua.util")
local choose = lw_utils.choose
local empty = lw_utils.empty
local is_array = lw_utils.is_array
local is_string = lw_utils.is_string
local is_number = lw_utils.is_number
local is_scalar = lw_utils.is_scalar
local in_array = lw_utils.in_array

---@type app
local app = ngx.ctx.app_context
---@class model
class.model()

---s属性初始化
---@protected
function model:properties()

    -- 当前数据库操作对象
    ---@type driver
    self.db = nil
    -- 数据库对象池
    self._db = {}
    -- 主键名称
    self.pk = 'id'
    -- 主键是否自动增长
    self.autoinc = false
    -- 数据表前缀
    self.tablePrefix = null
    -- 模型名称
    self.name = ''
    -- 数据库名称
    self.dbName = ''
    --数据库配置
    self.connection = ''
    -- 数据表名（不包含表前缀）
    self.tableName = ''
    -- 实际数据表名（包含表前缀）
    self.trueTableName = ''
    -- 最近错误信息
    self.error = ''
    -- 字段信息
    self.fields = {}
    -- 数据信息
    self.data = {}
    -- 查询表达式参数
    self.options = {}
    self._validate = {} -- 自动验证定义
    self._auto = {} -- 自动完成定义
    self._map = {} -- 字段映射定义
    self._scope = {} -- 命名范围定义
    -- 是否自动检测数据表字段信息
    self.autoCheckFields = true
    -- 是否批处理验证
    self.patchValidate = false
    -- 链操作方法列表
    self.methods = { 'strict', 'order', 'alias', 'having', 'group', 'lock', 'distinct', 'auto', 'filter', 'validate', 'result', 'token', 'index', 'force', 'master' }

end
---_init
---@param name string
---@param tablePrefix string
---@param connection any
---@return model
function model:_init(name, tablePrefix, connection)
    self:properties()
    connection = connection or ''

    self:_initialize()
    if name then
        if string.find(name, '\\.') then
            local names = split(name, '\\.')
            self.dbName = names[1]
            self.name = names[2]
        else
            self.name = name;
        end

    elseif not self.name then
        self.name = self:getModleName()
    end

    if not tablePrefix then
        self.tablePrefix = ''
    elseif '' ~= tablePrefix then
        self.tablePrefix = tablePrefix
    elseif not self.tablePrefix then
        self.tablePrefix = app:C(self.connection .. '.DB_PREFIX') or app:C('DB_PREFIX')
    end
    self:db_instance(1, connection or self.connection, true)
end

function model:getModleName()
end

function model:_initialize()
end

function model:_facade(data)
    local fields
    if not self.fields then
        if not self.options.field then
            fields = self.options.field
            self.options.field = nil
            if 'string' == type('fields') then
                fields = split(fields, ',')
            end
        else
            fields = self.fields
        end
        for key, val in pairs(data) do
            if not tablex.find(fields, key) then
                if self.options.strict then
                    error('data type not valid :[' .. key .. '=' .. val .. ']')
                end
            elseif type(val) then
                --is_scalar
                self:_parseType(data, key)
            end
        end
    end
    if self.options.filter then
        data = tablex.map(data, self.options.fiter)
        self.options.filter = nil
    end
    self:_before_write(data)
    return data
end

function model:_before_write(data)
end

function model:add(data, options, replace)
    if empty(data) then
        if self.data then
            data = self.data
            self.data = {}
        else
            return false
        end
    end
    data = self:_facade(data)
    options = self:_parseOptions(options)
    if not self:_before_insert(data, options) then
        return false
    end
    local result = self.db:insert(data, options, replace)
    if result and type(result) == 'number' then
        local pk = self:getPk()
        if type(pk) == 'table' then
            return result
        end
        local insertId = self:getLastInsID()
        if insertId then
            data[pk] = insertId
            if not self:_after_insert(data, options) then
                return false
            end
            return insertId
        end
        if not self:_after_insert(data, options) then
            return false
        end
    end
    return result
end

function model:_before_insert(data, options)
    return true
end

function model:_after_insert(data, options)
end

function model:_before_update(data, options)
end

function model:_after_update(data, options)
end

function model:addAll(dataList, options, replace)
    if empty(dataList) then
        return false
    end

    for key, data in pairs(dataList) do
        dataList[key] = self:_facade(data)
    end
    options = self:_parseOptions(options)
    local result = self.db:insertAll(dataList, options, replace)
    if result then
        local insertId = self:getLastInsID()
        if insertId then
            return insertId
        end
    end
    return result
end

function model:selectAdd(fields, table, options)
    options = self:_parseOptions(options)
    local result = self.db:selectInsert(fields or options['field'], table or self:getTableName(), options)
    if not result then
        --            $this->error = L('_OPERATION_WRONG_');

        return false
    else
        return result
    end
end

function model:save(data, options)
    if not data then
        if self.data then
            data = self.data
            self.data = {}
        else
            return false
        end
    end
    data = self:_facade(data)
    if not data then
        return false
    end
    options = self:_parseOptions(options)
    local pk = self:getPk()
    local where
    if not options.where then
        if type(pk) == 'string' and data.pk then
            where.pk = data.pk
            data.pk = nil
        else
            if type(pk) == 'table' then
                for i = 1, #pk do
                    if data.field then
                        where[#pk[i]] = data.field
                    else
                        --                        $this->error = L('_OPERATION_WRONG_');
                        return false
                    end
                end
                data.field = nil
            end
        end
        if not where then
            return false
        else
            options.where = where
        end
    end

    local pkValue
    if type(options.where) == 'table' and options.where[pk] then
        pkValue = options.where[pk]
    end
    if self:_before_update(data, options) then
        return false
    end

    local result = self.db:update(data, options)
    if result and type(result) == 'number' then
        if pkValue then
            data[pk] = pkValue
        end
        self:_after_update(data, options)
    end
    return result
end

function model:delete(options)
    local pk = self:getPk()
    local where = {}
    if not options and not self.options.where then
        if self.data and self.data[pk] then
            return self:delete(self.data[pk])
        else
            return false
        end
    end
    if type(options) == 'number' or type(options) == 'string' then
        if string.find(options, ',') then
            where[pk] = { 'IN', options }
        else
            where[pk] = options
        end
        self.options.where = where
    end
    if type(options) == 'table' and #options > 0 and type(pk) == 'table' then
        local count = 1
        for i = 1, #options do
            if type(options[i]) == 'number' then
                count = count + 1
            end
        end
        if #pk == count then
            local i = 1
            for k = 1, #pk do
                where[#pk[k]] = options[i]
                options.remove(i)
                i = i + 1
            end
            self.options.where = where
        else
            return false
        end
    end

    options = self:_parseOptions()
    if not options.where then
        return false
    end
    local pkValue
    if type(options.where) and options.where[pk] then
        pkValue = options.where[pk]
    end
    if not self:_before_delete(options) then
        return false
    end

    local result = self.db:delete(options)

    if not result and type(result) == 'number' then
        local data = {}
        if pkValue then
            data[pk] = pkValue
        end
        self:_after_delete(data, options)
    end
    return result
end

function model:_before_delete(options)
    return true
end

function model:_after_delete(data, options)
end

---查询数据
---@param options any
function model:select(options)
    local pk = self:getPk()
    local where = {}
    local cache
    if is_string(options) or is_number(options) then
        if string.find(options, ',') then
            where[pk] = { 'IN', options }
        else
            where[pk] = options
        end
        self.options.where = where
    elseif is_array(options) and #options > 0 and is_array(pk) then
        local count = 1
        local keys = tablex.keys(options)
        for i = 1, #keys do
            if type(keys[i]) == 'number' then
                count = count + 1
            end
        end
        if #pk == count then
            local i = 1
            for j = 1, #pk do
                where[#pk[j]] = options[j]
                options.remove(i)
                i = i + 1
            end
            self.options.where = where
        else
            return false
        end
    elseif false == options then
        self.options.fetch_sql = true
    end
    options = self:_parseOptions()
    local key
    if options.cache then
        cache = options.cache
        key = cache.key
        if type(cache.key) == 'table' then
            key = '' --- hash options
        end
        local data = self:S(key, '', cache)
        if data then
            return data
        end
    end
    local resultSet = self.db:select(options)
    if not resultSet then
        return false
    end
    if resultSet then
        if type(resultSet) == 'string' then
            return resultSet
        end
        resultSet = tablex.map(pl_utils.bind1(self._read_data, self), resultSet)
        self:_after_select(resultSet, options)
        if options.index then
            local index = split(options.index, ',')
            local cols
            for i = 1, #resultSet do
                local _key = resultSet[i][index[1]]
                if index[2] and resultSet[i][index[2]] then
                    cols[_key] = resultSet[i][index[2]]
                else
                    cols[_key] = resultSet[i]
                end
            end
            resultSet = cols
        end
    end
    if cache then
        self:S(key, resultSet, cache)
    end
    return resultSet
end

function model:_after_select()
end

function model:_parseOptions(options)
    options = options or {}
    local fields
    if is_array(options) then
        options = tablex.update(self.options, options)
    end
    if empty(options.table) then
        options.table = self:getTableName()
        fields = self.fields
    else
        fields = self:getDbFields()
    end

    if options.alias then
        options.table = options.table .. ' ' .. options.alias
    end

    options.model = self.name
    if is_array(options.where) and fields and empty(options.join) then
        lw_utils.foreach(options.where, function(val, key)
            key = stringx.strip(key)
            if in_array(fields, key) then
                if is_scalar(val) then
                    self:_parseType(options.where, key)
                end
            end
        end)
    end

    self.options = {}
    self:_options_filter(options)
    return options
end

function model:_options_filter(options)
    return options
end

function model:_parseType(data, key)
    if not self.options.bind[':' .. key] and self._fields._type[key] then
        local fieldType = string.lower(self._fields._type[key])
        if string.find(fieldType, 'enum') then
        elseif string.find(fieldType, 'bigint') and string.find(fieldType, 'int') then
            data[key] = tonumber(data[key])
        elseif string.find(fieldType, 'float') or string.find(fieldType, 'double') then
            --                $data[$key] = floatval($data[$key]);
            data[key] = tonumber(data[key])
        elseif string.find(fieldType, 'bool') then
            data[key] = not not data[key]
        end
    end
    return data
end

function model:_read_data(data)
    if not empty(self._map) and app:C('READ_DATA_MAP') then
        for k, v in pairs(self._map) do
            if data[v] then
                data[k] = data[v]
                data[v] = nil
            end
        end
    end

    return data
end

function model:get_hash_key(data)
    return data
end

function model:find(options)
    local where = {}
    if type(options) == 'string' or type(options) == 'number' then
        where[self:getPk()] = options
        self.options.where = where
    end
    local pk = self:getPk()
    if type(options) == 'table' and #options > 0 and type(pk) == 'table' then
        local count = 1
        local keys = tablex.keys(options)
        for i = 1, #keys do
            if type(keys[i]) == 'number' then
                count = count + 1
            end
        end
        if #pk == count then
            local j = 1
            for i = 1, #pk do
                where[pk[i]] = options[j]
                options.remove(j)
                j = j + 1
            end
            self.options.where = where
        else
            return false
        end
    end
    self.options.limit = 1
    options = self:_parseOptions()
    local cache, key, data

    if options.cache then
        cache = options.cache
        key = self:get_hash_key(options)
        data = self:S(key, '', cache)
        if data then
            return data
        end
    end

    local resultSet = self.db:select(options)
    if false == resultSet then
        return false
    end
    if not resultSet then
        return nil
    end
    if type(resultSet) == 'string' then
        return resultSet
    end

    data = self:_read_data(resultSet[1])

    self:_after_find(data, options)
    if options.result then
        return self:returnResult(data, options.result)
    end
    self.data = data

    if cache then
        self:S(key, data, cache)
    end
    return self.data
end

function model:_after_find(results, options)
end

---@param data table
---@param resultType any
function model:returnResult(data, resultType)
    if resultType then
        if type(resultType) == 'function' then
            return resultType(data)
        end
        resultType = string.lower(resultType)
        if resultType == 'json' then
            return json.encode(data)
        elseif resultType == 'xml' then
            return xml_encode(data)
        end
    end
    return data
end

---处理字段映射
---@param data table 当前数据
---@param fieldType number 类型 0 写入 1 读取
function model:parseFieldsMap(data, fieldType)
    --检查字段映射
    if self._map then
        for k, v in pairs(self._map) do
            if 1 == fieldType then
                if data[v] then
                    data[k] = data[v]
                    data[v] = nil
                end
            else
                if data[k] then
                    data[v] = data[k]
                    data[k] = nil
                end
            end
        end
    end
    return data
end
---设置记录的某个字段值
---@param field any
---@param value any
---@return any
function model:setField(field, value)
    local data
    if type(field) == 'table' then
        data = field
    else
        data[field] = value
    end
    return self:save(data)
end

---@param field string 字段名
---@param step number 增长值
---@param lazyTime number  延时时间(s)
---@return boolean
function model:setInc(field, step, lazyTime)
    step = step or 1
    lazyTime = lazyTime or 0

    if lazyTime > 0 then
        local condition = self.options.where
        local guid = md5(table.concat({ self.name, field, self:get_hash_key(condition) }, '_'))
        step = self:lazyWrite(guid, step, lazyTime)
        if not step then
            return true
        elseif step < 0 then
            step = '-' .. step
        end
    end
    return self:setField(field, { 'exp', field .. '+' .. step })
end

---@param field string 字段名
---@param step number 减少值
---@param lazyTime number 延时时间(s)
---@return boolean
function model:setDec(field, step, lazyTime)
    step = step or 1
    lazyTime = lazyTime or 0

    if lazyTime > 0 then
        local condition = self.options.where
        local guid = md5(table.concat({ self.name, field, self:get_hash_key(condition) }, '_'))
        step = self:lazyWrite(guid, -step, lazyTime)
        if not step then
            return true
        elseif step > 0 then
            step = '-' .. step
        end
    end
    return self:setField(field, { 'exp', field .. '-' .. step })
end
--- 延时更新检查 返回false表示需要延时
---@param guid string
---@param step number
---@param lazyTime number
function model:lazyWrite(guid, step, lazyTime)
    local value = self:S(guid)
    if false ~= value then
        if now() > self:S(guid .. '_time') + lazyTime then
            self:S(guid, nil)
            self:S(guid .. '_time', nil)
            return value + step
        else
            self:S(guid, value + step, 0)
            return false
        end
    else
        self:S(guid, step, 0)
        self:S(guid .. '_time', now(), 0)
        return false
    end
end
--- 获取一条记录的某个字段值
---@param field string 字段名
---@param sepa string 字段数据间隔符号
function model:getField(field, sepa)
    local options = {
        field = field
    }
    local cache, key
    options = self:_parseOptions(options)
    if options.cache then
        cache = options.cache
        key = self:get_hash_key(key, options)
        data = self:S(key, '', cache)
        if data then
            return data
        end
    end
    field = stringx.strip(field)
    if string.find(field, ',') and sepa then
        if options.limit then
            if type(sepa) == 'number' then
                options.limit = sepa
            else
                options.limit = ''
            end
        end
        local resultSet = self.db:select(options)
        if resultSet then
            if type(resultSet) == 'string' then
                return resultSet
            end
            local _field = split(field, ',')
            field = tablex.keys(resultSet[1])
            local key1 = field[1]
            field.remove(1)
            local key2 = field[1]
            field.remove(1)
            local count = #_field
            local cols = {}
            for i = 1, #resultSet do
                local result = resultSet[i]
                local name = result[key1]
                if 2 == count then
                    cols[name] = result[key2]
                else
                    if type(sepa) == 'string' then
                        cols[name] = '' --implode($sepa, array_slice($result, 1))
                    else
                        cols[name] = result
                    end

                end
            end
            if cache then
                self:S(key, cols, cache)
            end
            return cols
        end
    else
        local data
        if true ~= sepa then
            if options.limit then
                if type(sepa) == 'number' then
                    options.limit = sepa
                else
                    options.limit = ''
                end
            end
        end
        local result = self.db:select(options)
        if result then
            if type(result) == 'string' then
                return result
            end

            if true ~= self and 1 == options.limit then
                data = result[1]
                if cache then
                    self:S(key, data, cache)
                end
                return data
            end
            local array = {}
            tablex.foreachi(result, function(val)
                array[#array + 1] = val
            end)
            if cache then
                self:S(key, array, cache)
            end
            return array
        end
    end
    return nil
end

---@param data any
---@param type string 状态
function model:create(data, type)
    if not data then
        --todo
    end
end
--自动表单令牌验证
function model:autoCheckToken()
    --todo
end
--使用正则验证数据
function model:regex()
    --todo
end
--自动表单处理
function model:autoOperation()
    --todo
end
--自动表单验证
function model:autoValidation()
    --todo
end
---验证表单字段 支持批量验证
function model:_validationField()
    --todo
end

---根据验证因子验证字段
function model:_validationFieldItem()
    --todo
end
---验证数据 支持 in between equal length regex expire ip_allow ip_deny
function model:check()
    --todo
end
--存储过程返回多数据集
function model:procedure()
    --todo
end

---sql查询
---@param sql string
---@param parse table
function model:query(sql, parse, ...)
    if type(parse) ~= 'table' and type(parse) ~= 'boolean' then
        parse = { ... }
        --todo
        --            $parse = func_get_args();
        --            array_shift($parse);
    end
    sql = self:parseSql(sql, parse)
    return self.db:query(sql)
end

--- 执行SQL语句
---@param sql string
---@param parse table
function model:execute(sql, parse)
    if type(parse) ~= 'table' and type(parse) ~= 'boolean' then
        --todo
        --            $parse = func_get_args();
        --            array_shift($parse);
    end
    sql = self:parseSql(sql, parse)
    return self.db:execute(sql)
end

---解析SQL语句
---@param sql string  SQL指令
---@param parse boolean 是否需要解析SQL
function model:parseSql(sql, parse)
    if true == parse then
        local options = sefl:_parseOptions()
        sql = self.db:parseSql(sql, options)
    elseif type(parse) == 'table' then
        parse = tablex.map(parse, function(v)
            --escapeString
        end)
        sql = string.format(sql, parse)
    else
        sql = '' --todo strtr($sql, array('__TABLE__' => $this->getTableName(), '__PREFIX__' => $this->tablePrefix));
        local prefix = self.tablePrefix
        sql = '' --preg_replace_callback("/__([A-Z0-9_-]+)__/sU", function ($match) use ($prefix) {return $prefix . strtolower($match[1]);}, $sql);
    end
    self.db:setModel(self.name)
    return sql
end

---得到当前的数据对象名称
function model:getModelName()
    if not self.name then
        -- $name = substr(get_class($this), 0, -strlen(C('DEFAULT_M_LAYER')));
        --todo
    end

    return self.name

end

---得到完整的数据表名
function model:getTableName()
    if empty(self.tableName) then
        local tableName = pl_utils.choose(not self.tablePrefix, self.tablePrefix, '')
        if not empty(self.tableName) then
            tableName = tableName .. self.tableName
        else
            tableName = tableName .. self.name
        end
        self.trueTableName = string.lower(tableName)
    end
    return choose(not empty(self.dbName), self.dbName .. '.', '') .. self.trueTableName
end

---启动事务
function model:startTrans()
    self:commit()
    self.db:startTrans()
    return
end

function model:commit()
    return self.db:commit()
end

function model:rollback()
    return self.db:rollback()
end

---getError
function model:getError()
    return self.error
end
---getDbError
function model:getDbError()
    return self.db:getDbError()
end
---getLastInsID
function model:getLastInsID()
    return self.db:getLastInsID()
end

---getLastSql
function model:getLastSql()
    return self.db:getLastSql(self.name)
end

---获取主键名称
function model:getPk()
    return self.pk
end

---获取数据表字段信息
function model:getDbFields()
    local tableName
    if self.options.table then
        if type(options.table) == 'table' then
            local table = tablex.keys(options.table)[1]
        else
            tableName = options.table
            if string.find(table, '/') then
                return false
            end
        end

        local fields = self.db:getFields(tableName)
        return pl_utils.choose(fields, tablex.keys(fields), false)
    end
    if self.fields then
        local fields = self.fields
        fields._type = nil
        fields._pk = nil
        return fields
    end
    return false
end

---设置数据对象值
---@param data any
function model:data(data)
    if not data then
        return self.data
    end
    if type(data) ~= 'table' then
        return self
    end
    self.data = data
    return self
end

---指定当前的数据表
---@param tableName any
function model:table(tableName)
    local prefix = self.tablePrefix
    if type(tableName) == 'table' then
        self.options.table = tableName
    elseif tableName then
        --todo            $table = preg_replace_callback("/__([A-Z0-9_-]+)__/sU", function ($match) use ($prefix) {return $prefix . strtolower($match[1]);}, $table);
        self.options.table = tableName
    end
    return self
end

---USING支持 用于多表删除
---@param using any
function model:using(using)
    local prefix = self.tablePrefix
    if type(using) == 'table' then
        options.using = using
    elseif using then
        --todo $using = preg_replace_callback("/__([A-Z0-9_-]+)__/sU", function ($match) use ($prefix) {return $prefix . strtolower($match[1]);}, $using);
        self.options.using = using
    end
    return self
end

---查询SQL组装 join
---@param join any
---@param joinType string
function model:join(join, joinType)
    joinType = joinType or 'INNER'
    local prefix = self.tablePrefix
    if type(join) then
        --todo
    else
    end
    return self
end

---查询SQL组装 union
---@param union any
---@param all boolean
function model:union(union, all)
    --TODO
end

---查询缓存
---@param key any
---@param expire number
---@param cachetype string
function model:cache(key, expire, cachetype)
    if type(key) == 'number' and not expire then
        expire = key
        key = true
    end
    if false ~= key then
        self.options.cache = {
            key = key,
            expire = expire,
            type = cachetype
        }
    end
    return self
end

---指定查询字段 支持字段排除
---@param field any
---@param except boolean
function model:field(field, except)
    if true == field then
        local fields = self:getDbFields()
        field = fields or '*'
    elseif except then
        if type(field) == 'string' then
            field = split(field, ',')
        end
        local fields = self:getDbFields()
        -- todo   $field  = $fields ? array_diff($fields, $field) : $field;
    end

    self.options.field = field
    return self
end

---调用命名范围
---@param scope table
---@param args userdata
function model:scope(scope, args)
    --todo
end

---指定查询条件 支持安全过滤
---@param where any 条件表达式
---@param parse any 预处理参数
---@return model
function model:where(where, parse, ...)
    if not empty(parse) and is_string(parse) then
        if type(parse) ~= 'table' then
            parse = { ... }
        end
        parse = tablex.map(pl_utils.bind1(self.db.escapeString, self.db), parse)
    end
    if is_string(where) and '' ~= where then
        local map = {}
        map._string = where
        where = map
    end
    if self.options.where then
        self.options.where = tablex.update(options.where, where)
    else
        self.options.where = where
    end
    return self
end

---指定查询数量
---@param offset any 起始位置
---@param length any 查询数量
---@return model
function model:limit(offset, length)
    if not length and string.find(offset, ',') then
        local tmp = split(offset, ',')
        offset = tmp[1]
        length = tmp[2]
    end
    self.options.limit = tonumber(offset) .. choose(length, ',' .. tonumber(length), '')
    return self
end

---指定分页
---@param page any 页数
---@param listRows any 每页数量
---@return model
function model:page(page, listRows)
    if not listRows and string.find(page, ',') then
        local tmp = split(page, ',')
        page = tmp[1]
        listRows = tmp[2]
    end
    self.options.page = { tonumber(page), tonumber(listRows) }
    return self
end

---查询注释
---@param comment string 注释
---@return model
function model:comment(comment)
    self.options.comment = comment
    return self
end

---获取执行的SQL语句
---@param fetch boolean 是否返回sql
---@return model
function model:fetchSql(fetch)
    self.options.fetch_sql = fetch
    return self
end

---参数绑定
---@param key string 参数名
---@return model
function model:bind(key, ...)
    if type(key) == 'table' then
        self.options.bind = key
    else
        local params = { ... }
        if #params > 1 then
            self.options.bind[key] = params
        else
            self.options.bind[key] = value
        end
    end
    return self
end

---设置模型的属性值
---@param name string 名称
---@param value any 值
---@return model
function model:setProperty(name, value)
    if self[name] then
        self[name] = value
    end
    return self
end
function model:buildSql()
    return '( ' .. self:fetchSql(true):select() .. ' )'
end

---缓存字段信息
function model:F(tableName, fields)
    local cache_type = app:C('DB_FIELDS_CACHE_TYPE')
    local cache
    local cache_key = app:C('DB_FIELDS_CACHE_PREFIX') .. self.db.config.database .. tableName
    if cache_type == 'shdict' then
        cache = app:get_cache({
            type = cache_type,
            dict = app:C('SHDICIT_NAME')
        })
    elseif cache_type == 'redis' then
        cache = app:get_cache({
            type = cache_type,
            host = app:C('redis_host'),
            port = app:C('redis_port')
        })
    end
    if empty(fields) then
        return cache:get(cache_key)
    else
        cache:set(cache_key, fields)
    end
end

function model:_after_db()
end

function model:flush()

    self.db:setModel(self.name)
    local tableName = self:getTableName()
    local fields = self.db:getFields(tableName)
    --todo
    if not fields then
        return false
    end
    self.fields = tablex.keys(fields)
    self.fields['_pk'] = nil
    local type = {}
    for key, val in pairs(fields) do
        type[key] = val['type']
        if val.primary then
            if self.fields._pk then
                if type(self.fields._pk) == 'string' then
                    self.pk = { self.fields._pk }
                    self.fields._pk[#self.fields._pk + 1] = self.pk
                end
                self.pk[#self.pk + 1] = key
                self.fields._pk[#self.fields._pk + 1] = key
            else
                self.pk = key
                self.fields._pk = key
            end
            if val.autoinc then
                self.autoinc = true
            end
        end
    end
    self.fields._type = type
    if app:C('DB_FIELDS_CACHE') then
        self:F('_fields' .. string.lower(tableName), self.fields)
    end
end

function model:_checkTableInfo()
    if empty(self.fields) then
        if app:C('DB_FIELDS_CACHE') then
            local fields = self:F('_fields' .. string.lower(self:getTableName()))
            if fields then
                self.fields = fields
                if fields['_pk'] then
                    self.pk = fields['_pk']
                end
                return
            end
        end
        self:flush()
    end
end

---db 切换当前的数据库连接
---@param linkNum number 连接序号
---@param config table 数据库连接信息
---@param force boolean
---@return model
function model:db_instance(linkNum, config, force)
    if '' == linkNum and self.db then
        return self.db
    end

    if not self._db[linkNum] or force then
        if config and type(config) == 'string' and not string.find(config, '/') then
            config = app:C(config)
        end
        self._db[linkNum] = Db.getInstance(config)
    elseif not config then
        self._db[linkNum]:close()
        self._db[linkNum] = nil
        return ;
    end
    self.db = self._db[linkNum]
    self:_after_db()
    if self.name and self.autoCheckFields then
        self:_checkTableInfo()
    end

    return self
end

return model