local Service = {}
Service.__index = Service

function Service.new(ctx, dependencies)
    return setmetatable({
        ctx = ctx,
        dependencies = dependencies or {},
    }, Service)
end

function Service:repository(name, table_name, db_name)
    if self.dependencies[name] then return self.dependencies[name] end
    local Repository = require("Tilua.repository.repository")
    local repo = Repository.new(self.ctx, table_name, db_name)
    self.dependencies[name] = repo
    return repo
end

function Service:transaction(name, fn)
    local tx = self.ctx:transaction(name)
    if fn then return tx:run(fn) end
    return tx
end

function Service:with_transaction(fn, name)
    return self:transaction(name, fn)
end

return Service
