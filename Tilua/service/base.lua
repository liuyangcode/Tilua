--- Tilua.service.base
--- Business-logic layer between Controller and Model.
---
---   local UserService = require("Tilua.service.base").define()
---   function UserService:create(payload)
---     return self:model("User"):data(payload):add()
---   end

local class = require("Tilua.utils.class")

---@class service
local Service = class.define()

function Service:properties()
    self.ctx = nil
    self.name = ""
    ---@type table<string, model>
    self._models = {}
end

--- ctx: app context; name: optional service name
function Service:_construct(ctx, name)
    self:properties()
    self.ctx = ctx
    self.name = name or self.name or ""
end

--- Lazy model access: self:model("User") or self:model().User
function Service:model(name)
    if not name then
        return self.ctx.model
    end
    if self._models[name] then
        return self._models[name]
    end
    local m = self.ctx.model[name]
    self._models[name] = m
    return m
end

function Service:db()
    return self.ctx.db
end

function Service:cache()
    return self.ctx.cache
end

function Service:config(key)
    if key then
        return self.ctx:get_config(key)
    end
    return self.ctx.config
end

function Service:logger()
    return self.ctx.logger
end

--- Run fn inside a DB transaction (uses default connection)
function Service:transaction(fn)
    local db = self:db()
    -- db manager may expose instance; prefer model.db
    local driver = nil
    if self._models and next(self._models) then
        local _, m = next(self._models)
        driver = m and m.db
    end
    if not driver then
        -- try get a default model driver via a throwaway
        local ok, m = pcall(function()
            return self.ctx.model.__default or self.ctx.model["User"] or self.ctx.model["user"]
        end)
        if ok and m and m.db then
            driver = m.db
        end
    end
    if not driver or not driver.startTrans then
        -- no transaction support; just run
        return fn(self)
    end
    driver:startTrans()
    local ok, a, b, c = pcall(fn, self)
    if ok then
        driver:commit()
        return a, b, c
    end
    pcall(function()
        driver:rollback()
    end)
    return error(a)
end

--- Optional validation hook; override in subclass
function Service:validate(data, rules)
    return true, data
end

--- Raise / return service exception
function Service:fail(message, status, details)
    local Exception = require("Tilua.core.exception")
    error(Exception.service(message, status or 422, details), 0)
end

function Service:fail_not_found(message)
    self:fail(message or "Not Found", 404)
end

--- Fluent SQL builder bound to default/first model connection
function Service:query(table_name)
    local Query = require("Tilua.database.query")
    local m = nil
    if next(self._models) then
        local _, model = next(self._models)
        m = model
    end
    local db = (m and m.db) or (self.ctx.db and self.ctx.db())
    local b = Query.builder(db)
    if table_name then
        b:table(table_name)
    end
    return b
end

return Service
