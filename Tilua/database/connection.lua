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

--- Split comma-separated host lists for deploy/rw_separate
function Connection:resolve_endpoint(master)
    local c = self.config
    local function split_csv(s)
        if type(s) ~= "string" or s == "" then return { s } end
        local t = {}
        for part in string.gmatch(s, "[^,]+") do
            t[#t + 1] = part:match("^%s*(.-)%s*$")
        end
        return #t > 0 and t or { s }
    end
    local hosts = split_csv(c.hostname or c.host or "127.0.0.1")
    local ports = split_csv(tostring(c.hostport or c.port or 3306))
    local users = split_csv(c.username or c.user or "")
    local pwds  = split_csv(c.password or c.pwd or "")
    local dbs   = split_csv(c.database or c.db_name or "")
    local charsets = split_csv(c.charset or "utf8mb4")

    local n = #hosts
    local deploy = tonumber(c.deploy) or 0
    local rw = c.rw_separate == true or c.rw_separate == 1 or c.rw_separate == "1"
    local master_num = tonumber(c.master_num) or 1
    if master_num < 1 then master_num = 1 end
    if master_num > n then master_num = n end

    local idx
    if deploy == 0 or n == 1 then
        idx = 1
    elseif rw then
        if master then
            idx = math.random(1, master_num)
        else
            if type(c.slave_no) == "number" then
                idx = c.slave_no
            elseif n > master_num then
                idx = math.random(master_num + 1, n)
            else
                idx = math.random(1, n)
            end
        end
    else
        idx = math.random(1, n)
    end
    if idx < 1 then idx = 1 end
    if idx > n then idx = n end

    return {
        hostname = hosts[idx] or hosts[1],
        hostport = tonumber(ports[idx] or ports[1]) or 3306,
        username = users[idx] or users[1],
        password = pwds[idx] or pwds[1],
        database = dbs[idx] or dbs[1],
        charset  = charsets[idx] or charsets[1],
        role = master and "master" or "slave",
        index = idx,
    }
end

--- Open (or reuse) resty.mysql connection for linkNum
function Connection:connect_mysql(linkNum, master)
    if master == nil then master = true end
    -- separate pools: master=1, slave=2 (+ index offset for multi-slave)
    local ep = self:resolve_endpoint(master)
    linkNum = linkNum or (master and 1 or (100 + (ep.index or 1)))

    if self.link_id[linkNum] then
        self._sock = self.link_id[linkNum]
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
    -- unique pool name per endpoint for resty.mysql
    local pool_name = c.pool or string.format("%s:%s:%s", ep.hostname, ep.hostport, ep.database or "")

    local ok, err2, errcode, sqlstate = db:connect({
        host = ep.hostname,
        port = ep.hostport,
        database = ep.database,
        user = ep.username,
        password = ep.password,
        charset = ep.charset or DEFAULTS.charset,
        max_packet_size = tonumber(c.max_packet_size) or DEFAULTS.max_packet_size,
        pool = pool_name,
        pool_size = tonumber(c.pool_size) or DEFAULTS.pool_size,
        backlog = c.backlog,
    })
    if not ok then
        if self.logger and self.logger.error then
            self.logger:error("mysql connect failed [", ep.role, "] ", ep.hostname, ": ", err2, " ", errcode, " ", sqlstate)
        end
        return nil, err2
    end

    if self.logger and self.logger.debug and c.debug then
        self.logger:debug("mysql connected [", ep.role, "] ", ep.hostname, ":", ep.hostport, " ver=", db:server_ver())
    end

    self.link_id[linkNum] = db
    self._sock = db
    self._last_role = ep.role
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
