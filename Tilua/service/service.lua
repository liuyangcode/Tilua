local Service = {}
Service.__index = Service

function Service.new(ctx, dependencies)
    return setmetatable({
        ctx = ctx,
        dependencies = dependencies or {},
    }, Service)
end

function Service:repository(name, table_name, db_name)
    if self.dependencies[name] then
        return self.dependencies[name]
    end
    local Repository = require("Tilua.repository.repository")
    local repo = Repository.new(self.ctx, table_name, db_name)
    self.dependencies[name] = repo
    return repo
end

function Service:transaction(name)
    return self.ctx:transaction(name)
end

return Service
