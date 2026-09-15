local class = require("Tilua.utils.class")

local DatabaseManager = class.define()

function DatabaseManager:_construct(config, container, logger)
    self.config = config or {}
    self.container = container
    self.logger = logger
end

function DatabaseManager:driver(name)
    name = name or self.config.default or "mysql"
    local cfg = self.config[name] or self.config
    local driver_name = cfg.driver or name
    if driver_name == "mysql" then
        return require("Tilua.database.driver.mysql")
    end
    return require("Tilua.db.driver." .. driver_name)
end

function DatabaseManager:connection(ctx, name)
    local Connection = require("Tilua.database.connection")
    return Connection.new(self, ctx, name)
end

function DatabaseManager:transaction(ctx, name)
    local Transaction = require("Tilua.database.transaction")
    return Transaction.new(self:connection(ctx, name))
end

return DatabaseManager
