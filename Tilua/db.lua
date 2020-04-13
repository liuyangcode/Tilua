

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
            type = app:C('db_type'),
            username = app:C('db_user'),
            password = app:C('db_pwd'),
            hostname = app:C('db_host'),
            hostport = app:C('db_port'),
            database = app:C('db_name'),
            charset = app:C('db_charset'),
            deploy = app:C('db_deploy_type'),
            rw_separate = app:C('db_rw_separate'),
            master_num = app:C('db_master_num'),
            slave_no = app:C('db_slave_no'),
            debug = app:C('db_debug', app.debug)
        }
    end
    return config
end

function db.close()
    log.record(log.DEBUG, 'run db connections instance handle close')
    lw_util.foreach(instance, function(db_inst)
        db_inst:close()
    end)
end
return db
