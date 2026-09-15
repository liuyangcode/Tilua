local Repository = {}
Repository.__index = Repository

function Repository.new(ctx, table_name, db_name)
    if not ctx then error("repository requires context") end
    return setmetatable({
        ctx = ctx,
        table = table_name,
        db_name = db_name,
    }, Repository)
end

function Repository:db()
    return self.ctx:db(self.db_name)
end

function Repository:query()
    local Query = require("Tilua.database.query")
    return Query.new(self:db())
end

function Repository:raw(sql, ...)
    return self:query():raw(sql, ...)
end

function Repository:find_all(sql, ...)
    return self:query():select(sql, ...)
end

return Repository
