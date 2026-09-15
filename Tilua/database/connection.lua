local Connection = {}
Connection.__index = Connection

function Connection.new(manager, ctx, name)
    local self = setmetatable({}, Connection)
    self.manager = manager
    self.ctx = ctx
    self.name = name or manager.config.default or "mysql"
    self.config = manager.config[self.name] or manager.config
    self.logger = manager.logger
    self.driver = manager:driver(self.name)
    return self
end

function Connection:open()
    if self.instance then return self.instance end

    local ok, instance = pcall(function()
        return self.driver(self.config, self.ctx, self.logger)
    end)
    if not ok then
        return nil, instance
    end

    self.instance = instance
    return instance
end

function Connection:query(sql, ...)
    local db, err = self:open()
    if not db then return nil, err end
    return db:query(sql, ...)
end

function Connection:select(sql, ...)
    local db, err = self:open()
    if not db then return nil, err end
    return db:select(sql, ...)
end

function Connection:execute(sql, ...)
    return self:query(sql, ...)
end

function Connection:begin()
    local db, err = self:open()
    if not db then return nil, err end
    self.in_transaction = true
    return db:beginTransaction()
end

function Connection:commit()
    if not self.instance then return true end
    local result = self.instance:commitTrans()
    self.in_transaction = false
    return result
end

function Connection:rollback()
    if not self.instance then return true end
    local db = self.instance
    self.in_transaction = false
    if db.rollbackTrans then
        return db:rollbackTrans()
    end
    return true
end

function Connection:close()
    if not self.instance then return end
    if self.instance.close then
        self.instance:close()
    end
    self.instance = nil
    self.in_transaction = false
end

return Connection
