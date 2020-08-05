---@class mysql
local mysql = require("Tilua.db.driver").define()
local mysqlc = require "resty.mysql"
local stringx = require "pl.stringx"
local lower = string.lower
local tablex = require("pl.tablex")
local foreach = tablex.foreach
local split = stringx.split

function mysql:connect(config, linkNum, autoConnection)
    linkNum = linkNum or 1
    autoConnection = autoConnection or false
    if not self.linkID[linkNum] then
        if not config then
            config = self.config
        end
        mysqlc:set_timeout(1000)
        local db, err = mysqlc:new()
        if not db then
            self.logger:error("failed to instantiate mysql: " .. err)
        end
        local ok, err, errcode, sqlstate = db:connect({
            host = config.hostname,
            port = config.hostport,
            database = config.database,
            user = config.username,
            password = config.password,
            charset = config.charset,
            max_packet_size = 1024 * 1024,
        })
        if not ok then
            self.logger:error("failed to connect: ", err, ":", (errcode or ""), " ", (sqlstate or ""))
        elseif self.debug then
            self.logger:debug("Mysql Connect success!Server version:", (db:server_ver() or ""), " reused times:", db:get_reused_times())
        end
        self.linkID[linkNum] = db
    end
    return self.linkID[linkNum]
end

function mysql:beginTransaction()
    self:initConnect(true)
    local res, err, errcode, sqlstate = self._linkID:query("START TRANSACTION")
    self.logger:debug("START TRANSACTION ")
    if not res then
        self.logger:error(err, " errcode ", (errcode or ""), " sqlstate:", (sqlstate or ""))
        error(err .. " errcode " .. (errcode or "") .. " sqlstate:" .. (sqlstate or ""),2)
    end
    return true
end

function mysql:commitTrans()
    self:initConnect(true)
    local res, err, errcode, sqlstate = self._linkID:query("COMMIT")
    self.logger:debug("COMMIT TRANSACTION ")
    if not res then
        self.logger:error(err, " errcode ", (errcode or ""), " sqlstate:", (sqlstate or ""))
        error(err .. " errcode " .. (errcode or "") .. " sqlstate:" .. (sqlstate or ""),2)
    end
    return true
end

function mysql:execute_sql(sql)
    local res, err, errcode, sqlstate = self._linkID:query(sql)
    if not res then
        self.logger:error(err, " errcode ", (errcode or ""), " sqlstate:", (sqlstate or ""))
        return nil,err .. " errcode " .. (errcode or "") .. " sqlstate:" .. (sqlstate or "")
    end
    self.numRows = #res
    self.result_sets = res
    return res
end

function mysql:close()
    if self._linkID then
        local ok, err = self._linkID:set_keepalive(60000, 100)
        if not ok then
            self.logger:error("failed to set keepalive because ", err)
        else
            self.logger:debug("set mysql host ",self.config.hostname," connection keepalive success!")
        end
    end
end

function mysql:getFields(tableName)
    self:initConnect(true)
    local tmp = split(tableName, ' ')
    tableName = tmp[1]
    local sql
    if stringx.lfind(tableName, '.') then
        tmp = split(tableName, '\\.')
        local dbName = tmp[1]
        tableName = tmp[2]
        sql = 'SHOW COLUMNS FROM `' .. dbName .. '`.`' .. tableName .. '`'
    else
        sql = 'SHOW COLUMNS FROM `' .. tableName .. '`'
    end
    local result, err = self:execute_sql(sql)
    if not result then
        error(err)
    end
    local info = {}
    foreach(result, function(val, key)
        foreach(val, function(v, k)
            val[lower(k)] = v
        end)
        info[val.field] = {
            name = val.field,
            type = val.type,
            notnull = '' == val.null,
            default = val.default,
            primary = lower(val.key) == 'pri',
            autoinc = lower(val.extra) == 'auto_increment'
        }
    end)
    return info
end

return mysql