

local lw_util = require('Tilua.util')
local get_hash = lw_util.get_hash
local log = require("Tilua.log")
---@type app
local app = ngx.ctx.app_context
local instance = {}
local _instance = nil
---@class db
local db = {}

function db.getInstance(config)
    assert(not lw_util.is_array(config), 'config must be not empty table')
    local hash = get_hash(config)
    if not instance[hash] then
        local options = db.parseConfig(config)
        local driver_type = string.lower(options.type)
        assert(driver_type == 'mysql', 'not support db driver' .. driver_type)
        local db_driver = require("Tilua.db.driver." .. driver_type)
        instance[hash] = db_driver(options)
    end
    _instance = instance[hash]
    return _instance
end

function db.parseConfig(config)
    if not lw_util.empty(config) then
    else
        config = {
            type = app:C('DB_TYPE'),
            username = app:C('DB_USER'),
            password = app:C('DB_PWD'),
            hostname = app:C('DB_HOST'),
            hostport = app:C('DB_PORT'),
            database = app:C('DB_NAME'),
            dsn = app:C('DB_DSN'),
            params = app:C('DB_PARAMS'),
            charset = app:C('DB_CHARSET'),
            deploy = app:C('DB_DEPLOY_TYPE'),
            rw_separate = app:C('DB_RW_SEPARATE'),
            master_num = app:C('DB_MASTER_NUM'),
            slave_no = app:C('DB_SLAVE_NO'),
            debug = app:C('DB_DEBUG', app.debug),
            lite = app:C('DB_LITE')
        }
    end
    return config
end

function db.close()
    log.record(ngx.DEBUG, 'run db connections instance handle close')
    lw_util.foreach(instance, function(db_inst)
        db_inst:close()
    end)
end
return db
