--- Tilua.database.connection
--- Connection lifecycle for SQL drivers (connect / keepalive / close)

local Connection = {}
Connection.__index = Connection

local DEFAULTS = {
    timeout = 2000,
    pool_size = 50,
    pool_timeout = 60000,
    charset = "utf8mb4",
    max_packet_size = 1024 * 1024,
    hostport = 3306,
}

function Connection.new(config, logger)
    local self = setmetatable({}, Connection)
    self.config = {}
    for k, v in pairs(DEFAULTS) do
        self.config[k] = v
    end
    if config then
        for k, v in pairs(config) do
            self.config[k] = v
        end
    end
    self.logger = logger
    self._sock = nil
    self.link_id = {}
    return self
end

function Connection:cfg()
    return self.config
end

--- Open (or reuse) resty.mysql connection for linkNum
function Connection:connect_mysql(linkNum)
    linkNum = linkNum or 1
    if self.link_id[linkNum] then
        return self.link_id[linkNum]
    end

    local ok_m, mysqlc = pcall(require, "resty.mysql")
    if not ok_m or not mysqlc then
        return nil, "resty.mysql not available"
    end

    local db, err = mysqlc:new()
    if not db then
        return nil, err
    end

    local c = self.config
    db:set_timeout(tonumber(c.timeout) or DEFAULTS.timeout)

    local ok, err2, errcode, sqlstate = db:connect({
        host = c.hostname or c.host or "127.0.0.1",
        port = tonumber(c.hostport or c.port) or 3306,
        database = c.database or c.db_name,
        user = c.username or c.user or c.db_user,
        password = c.password or c.pwd or c.db_pwd,
        charset = c.charset or DEFAULTS.charset,
        max_packet_size = tonumber(c.max_packet_size) or DEFAULTS.max_packet_size,
        pool = c.pool,
        pool_size = tonumber(c.pool_size) or DEFAULTS.pool_size,
        backlog = c.backlog,
    })
    if not ok then
        if self.logger and self.logger.error then
            self.logger:error("mysql connect failed: ", err2, " ", errcode, " ", sqlstate)
        end
        return nil, err2
    end

    if self.logger and self.logger.debug and c.debug then
        self.logger:debug("mysql connected ", c.hostname, " ver=", db:server_ver())
    end

    self.link_id[linkNum] = db
    self._sock = db
    return db
end

function Connection:sock(linkNum)
    return self.link_id[linkNum or 1] or self._sock
end

function Connection:set_active(sock)
    self._sock = sock
end

function Connection:keepalive(linkNum)
    local db = self.link_id[linkNum or 1] or self._sock
    if not db then
        return true
    end
    local idle = tonumber(self.config.pool_timeout) or DEFAULTS.pool_timeout
    local size = tonumber(self.config.pool_size) or DEFAULTS.pool_size
    local ok, err = db:set_keepalive(idle, size)
    if not ok and self.logger then
        self.logger:error("mysql keepalive failed: ", err)
    end
    self.link_id[linkNum or 1] = nil
    if self._sock == db then
        self._sock = nil
    end
    return ok, err
end

function Connection:close()
    for num, _ in pairs(self.link_id) do
        self:keepalive(num)
    end
    if self._sock then
        pcall(function()
            self._sock:set_keepalive(
                tonumber(self.config.pool_timeout) or DEFAULTS.pool_timeout,
                tonumber(self.config.pool_size) or DEFAULTS.pool_size
            )
        end)
        self._sock = nil
    end
end

return Connection
