
---@class mysql
local mysql = require("Tilua.db.driver").derive()
local mysqlc = require "resty.mysql"
local stringx = require "pl.stringx"
local lower = string.lower
local tablex = require("pl.tablex")
local foreach = tablex.foreach
local split = stringx.split
local log = require("Tilua.log")
function mysql:_init(config)
    self:super(config)
end

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
            error("failed to instantiate mysql: " .. err)
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
            error("failed to connect: " .. err .. ":" .. (errcode or "") .. " " .. (sqlstate or ""))
        end
        self.linkID[linkNum] = db
    end
    return self.linkID[linkNum]
end

function mysql:execute_sql(sql)
    local res, err, errcode, sqlstate = self._linkID:query(sql)
    if not res then
        error(err .. " errcode " .. (errcode or "") .. " sqlstate:" .. (sqlstate or ""))
    end
    self.numRows = #res
    self.result_sets = res
    return res
end

---将连接放入连接池
function mysql:set_keepalive_mod()
    return self._linkID and self._linkID:set_keepalive(10000, 1000)
end

function mysql:close()
    local ok, err = self:set_keepalive_mod()
    if not ok then
        log.record(ngx.ERR, "failed to set keepalive:", err)
    end
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