local string_find = string.find
local table_concat = table.concat
---@class log
local log = {
    STDERR = "STDERR",
    EMERG = "EMERG",
    ALERT = "ALERT",
    CRIT = "CRIT",
    ERR = "ERROR",
    WARN = "WARN",
    NOTICE = "NOTICE",
    INFO = "INFO",
    DEBUG = "DEBUG",
    NONE = "NONE"
}
local mt = {
    __index = log
}
---@type app

function log:write(...)
    self:record("", ...)
end

function log:record(level, ...)
    if level == log.NONE then
        return true
    end
    if string_find(self.config.level,level,1,true) then
        self.log_data[#self.log_data + 1] = {
            level = level,
            msg = table_concat({...})
        }
    end
    return true
end

function log:debug(...)
    self:record(log.DEBUG,...)
end

function log:info(...)
    self:record(log.INFO, ...)
end

function log:error(...)
    self:record(log.ERR,...)
end

function log:flush()
    self.handler.flush(self)
end

function log.new(cfg)
    return setmetatable({
        log_data = {},
        config = cfg
    },mt)
end

function log.init(cfg)
    _, log.handler = pcall(require, "Tilua.log." .. cfg.type)
    log.handler.init(cfg)
    return log
end

return log