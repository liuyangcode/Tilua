local lw_util = require('Tilua.util')
local get_hash = lw_util.get_hash
---@class db
local db = {}
local mt = {
    __index = db
}
function db:instance(config)
    config = self:parse_config(config)
    local hash = get_hash(config)
    if not self.instances[hash] then
        local driver_type = string.lower(config.type)
        assert(driver_type == 'mysql', 'not support db driver' .. driver_type)

        self.ctx.logger:debug("start init db driver named ",driver_type," with config ",lw_util.json_encode(config))
        local db_driver = require("Tilua.db.driver." .. driver_type)
        self.instances[hash] = db_driver(config)
    end
    return self.instances[hash]
end

function db:parse_config(config)
    if not lw_util.empty(config) then
        return config
    else
        local db_config = self.ctx.config
        config = {
            type = db_config.db_type,
            username = db_config.db_user,
            password = db_config.db_pwd,
            hostname = db_config.db_host,
            hostport = db_config.db_port,
            database = db_config.db_name,
            charset = db_config.db_charset,
            --deploy = app:C('db_deploy_type'),
            --rw_separate = app:C('db_rw_separate'),
            --master_num = app:C('db_master_num'),
            --slave_no = app:C('db_slave_no'),
            debug = db_config.db_debug
        }
    end
    return config
end

function db:close()
    self.ctx.logger:debug('db connections instance handle close')
    lw_util.foreach(self.instances, function(db_inst)
        db_inst:close()
    end)
end

function db.new(ctx)
    return setmetatable({
        instances = {},
        ctx = ctx
    }, mt)
end

return db
