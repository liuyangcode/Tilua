local Transaction = {}
Transaction.__index = Transaction

function Transaction.new(connection)
    return setmetatable({ connection = connection, active = false }, Transaction)
end

function Transaction:begin()
    if self.active then return true end
    local ok, err = self.connection:begin()
    if ok == false or ok == nil then return nil, err end
    self.active = true
    return true
end

function Transaction:commit()
    if not self.active then return true end
    local ok, err = self.connection:commit()
    if ok == false or ok == nil then return nil, err end
    self.active = false
    return true
end

function Transaction:rollback()
    if not self.active then return true end
    local ok, err = self.connection:rollback()
    self.active = false
    if ok == false then return nil, err end
    return true
end

function Transaction:run(fn)
    if type(fn) ~= "function" then return nil, "invalid_transaction_callback" end
    local ok, err = self:begin()
    if not ok then return nil, err end

    local success, result = xpcall(fn, debug.traceback)
    if not success then
        self:rollback()
        return nil, result
    end

    if result == false then
        self:rollback()
        return false
    end

    local committed, commit_err = self:commit()
    if not committed then
        self:rollback()
        return nil, commit_err
    end
    return result
end

return Transaction
