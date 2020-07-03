---@class mysql
local mysql = require("Tilua.db.driver").derive()
local mysqlc = require "resty.mysql"
local stringx = require "pl.stringx"
local lower = string.lower
local tablex = require("pl.tablex")
local foreach = tablex.foreach
local split = stringx.split
function mysql:_init(...)
    self:super(...)
end

function mysql:connect(config, linkNum, autoConnection)
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
        self.logger:debug("Mysql Connect success!Server version:", (db:server_ver() or " null "), " reused times:", db:get_reused_times() or " null ")
    end
    return db
end

function mysql:execute_sql(sql)
    local db = self._linkID
    local res, err, errcode, sqlstate = db:query(sql)
    if not res or err then
        self.logger:error(err, " errcode ", (errcode or ""), " sqlstate:", (sqlstate or ""))
        error(err .. " errcode " .. (errcode or "") .. " sqlstate:" .. (sqlstate or ""), 2)
        return nil
    end
    local ok, _err = db:set_keepalive(60000, 100)
    if not ok then
        self.logger:error("failed to set keepalive because ", _err)
    else
        self.logger:debug("set mysql host ", self.config.hostname, " connection keepalive success!")
    end
    self.numRows = #res
    self.result_sets = res
    return res
end

function mysql:close()
    self._linkID = nil
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
    local result = self:execute_sql(sql)
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