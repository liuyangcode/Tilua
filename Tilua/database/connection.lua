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
    if not ok then return nil, instance end
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
    local db, err = self:open()
    if not db then return nil, err end
    if db.execute then return db:execute(sql, ...) end
    return db:query(sql, ...)
end

function Connection:begin()
    local db, err = self:open()
    if not db then return nil, err end
    local ok, result = pcall(function() return db:beginTransaction() end)
    if not ok then return nil, result end
    self.in_transaction = true
    return result ~= false, result
end

function Connection:commit()
    if not self.instance or not self.in_transaction then return true end
    local ok, result = pcall(function() return self.instance:commitTrans() end)
    self.in_transaction = false
    if not ok then return nil, result end
    return result ~= false, result
end

function Connection:rollback()
    if not self.instance or not self.in_transaction then return true end
    local db = self.instance
    local ok, result = pcall(function()
        if db.rollbackTrans then return db:rollbackTrans() end
        if db._linkID then return db._linkID:query("ROLLBACK") end
        return false
    end)
    self.in_transaction = false
    if not ok then return nil, result end
    if result == false then return nil, "rollback failed" end
    return true
end

function Connection:close()
    if not self.instance then return true end
    if self.in_transaction then pcall(function() self:rollback() end) end
    if self.instance.close then pcall(self.instance.close, self.instance) end
    self.instance = nil
    self.in_transaction = false
    return true
end

return Connection
