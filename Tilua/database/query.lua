local Query = {}
Query.__index = Query

function Query.new(connection)
    return setmetatable({ connection = connection }, Query)
end

function Query:raw(sql, ...)
    return self.connection:query(sql, ...)
end

function Query:select(sql, ...)
    return self.connection:select(sql, ...)
end

return Query
