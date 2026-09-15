--- Tilua.database.manager
--- Connection/driver pool keyed by config hash

local helpers = require("Tilua.core.helpers")
local lw_utils = require("Tilua.utils.util")

local Manager = {}
Manager.__index = Manager

local function parse_config(ctx, config)
    local t = type(config)
    if t == "string" and config ~= "" then
        local dsn = lw_utils.parse_url and lw_utils.parse_url(config)
        if dsn then
            return {
                type = dsn.scheme or "mysql",
                username = dsn.user,
                password = dsn.pass,
                hostname = dsn.host,
                hostport = dsn.port,
                database = dsn.path and dsn.path:sub(2) or "",
                charset = dsn.fragment or "utf8mb4",
                debug = dsn.params and dsn.params.debug,
            }
        end
        local named = ctx and ctx[config]
        if type(named) == "table" then
            return helpers.deepcopy(named)
        elseif type(named) == "string" then
            return parse_config(ctx, named)
        end
        return nil
    elseif t == "table" then
        return config
    elseif t == "nil" or (t == "string" and #config == 0) then
        local c = ctx or {}
        return {
            type = c.db_type or "mysql",
            username = c.db_user,
            password = c.db_pwd,
            hostname = c.db_host,
            hostport = c.db_port,
            database = c.db_name,
            charset = c.db_charset or "utf8mb4",
            debug = c.db_debug,
            timeout = c.db_timeout,
            pool_size = c.db_pool_size,
            pool_timeout = c.db_pool_timeout,
        }
    end
end

function Manager.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Manager)
    self.ctx = opts.ctx
    self.logger = opts.logger
    self.instances = {}
    return self
end

function Manager:instance(config)
    if config == self then
        config = nil
    end
    config = parse_config(self.ctx, config)
    assert(config, "db config is not valid")

    local hash = (lw_utils.get_hash and lw_utils.get_hash(config)) or tostring(config.hostname) .. ":" .. tostring(config.database)
    if self.instances[hash] then
        return self.instances[hash]
    end

    local driver_type = string.lower(config.type or "mysql")
    assert(driver_type == "mysql", "unsupported db driver: " .. driver_type)

    if self.logger and self.logger.debug then
        self.logger:debug("init database driver ", driver_type, " host=", config.hostname)
    end

    local Mysql = require("Tilua.database.driver.mysql")
    local driver = Mysql.new(config, self.ctx, self.logger)
    self.instances[hash] = driver
    return driver
end

function Manager:close()
    if self.logger and self.logger.debug then
        self.logger:debug("closing database instances")
    end
    for _, inst in pairs(self.instances) do
        if inst.close then
            pcall(function()
                inst:close()
            end)
        end
    end
    self.instances = {}
end

--- Callable manager: manager() or manager["default"]
local function create(opts)
    local m = Manager.new(opts)
    return setmetatable(m, {
        __index = function(this, name)
            local raw = rawget(Manager, name)
            if type(raw) == "function" then
                return function(_, ...)
                    return raw(this, ...)
                end
            end
            if type(raw) ~= "nil" and name ~= "new" then
                return raw
            end
            return Manager.instance(this, name)
        end,
        __call = function(this, config)
            return Manager.instance(this, config)
        end,
    })
end

return setmetatable({
    new = Manager.new,
    create = create,
}, {
    __call = function(_, opts)
        return create(opts)
    end,
})
