--- Tilua.database.transaction
--- Nested-safe transaction helper over a connection/driver

local Transaction = {}
Transaction.__index = Transaction

function Transaction.new(driver)
    local self = setmetatable({}, Transaction)
    self.driver = driver
    self.depth = 0
    return self
end

function Transaction:begin()
    local d = self.driver
    if not d then
        return false, "no driver"
    end
    if self.depth == 0 then
        if d.beginTransaction then
            d:beginTransaction()
        elseif d.startTrans then
            d:startTrans()
        else
            return false, "driver has no begin"
        end
    end
    self.depth = self.depth + 1
    return true
end

function Transaction:commit()
    if self.depth <= 0 then
        return true
    end
    self.depth = self.depth - 1
    if self.depth == 0 then
        local d = self.driver
        if d.commitTrans then
            return d:commitTrans()
        end
        if d.commit then
            return d:commit()
        end
    end
    return true
end

function Transaction:rollback()
    local d = self.driver
    self.depth = 0
    if d.rollback then
        return d:rollback()
    end
    return false
end

--- Run fn inside transaction; auto commit/rollback
function Transaction:run(fn)
    local ok_b, err_b = self:begin()
    if not ok_b then
        return nil, err_b
    end
    local ok, a, b, c = pcall(fn)
    if ok then
        self:commit()
        return a, b, c
    end
    pcall(function()
        self:rollback()
    end)
    return nil, a
end

--- Functional helper without instance
function Transaction.using(driver, fn)
    return Transaction.new(driver):run(fn)
end

return Transaction
