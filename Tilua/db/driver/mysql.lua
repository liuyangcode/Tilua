--- Shim: Tilua.db.driver.mysql → Tilua.database.driver.mysql
local Mysql = require("Tilua.database.driver.mysql")
local M = {}
function M.new(config, ctx, logger)
    return Mysql.new(config, ctx, logger)
end
function M.define()
    return setmetatable({}, {
        __call = function(_, config, ctx, logger)
            return Mysql.new(config, ctx, logger)
        end,
        __index = Mysql,
    })
end
setmetatable(M, {
    __call = function(_, config, ctx, logger)
        return Mysql.new(config, ctx, logger)
    end,
})
return M
