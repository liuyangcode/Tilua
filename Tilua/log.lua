local string_find = string.find
local table_concat = table.concat
local import = require("Tilua.utils.util").import

---@class log
local log = {
    STDERR = "STDERR",
    EMERG = "EMERG",
    ALERT = "ALERT",
    CRIT = "CRIT",
    ERR = "ERR",
    WARN = "WARN",
    NOTICE = "NOTICE",
    INFO = "INFO",
    DEBUG = "DEBUG",
    NONE = "NONE"
}

local mt = {
    __index = log
}

local function enrich_message(context, args)
    if not context then
        return args
    end

    local trace_id = nil
    if type(context) == "table" then
        trace_id = context.trace_id
        if not trace_id and context.trace then
            trace_id = context.trace.trace_id
        end
    end

    if trace_id then
        table.insert(args, 1, "[trace_id=" .. trace_id .. "]")
    end

    return args
end

function log:write(...)
    self:record("", ...)
end

function log:record(level, ...)
    if level == log.NONE then
        return true
    end

    if self.config.type ~= 'syslog' then
        if string_find(self.config.level, level, 1, true) then
            self.log_data[#self.log_data + 1] = {
                level = level,
                msg = table_concat({ ... })
            }
        end
    else
        if string_find(self.config.level, level, 1, true) then
            ngx.log(ngx[level] or ngx.INFO, ...)
        end
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

-- P1: structured context aware logging
function log:context(level, context, ...)
    local args = enrich_message(context, {...})
    self:record(level, table_concat(args, " "))
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
    log.handler = import("Tilua.log." .. cfg.type)
    if log.handler then
        log.handler.init(cfg)
    end
    return log
end

return log