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
local _logdata = {}
function log.record(level, msg, force)
    if level == log.NONE then return true end
    if force or level then end
    _logdata[#_logdata + 1 ] = string.format("%s:%s",level,msg)
    return true
end

function log.debug(msg, ...)
    log.record(log.DEBUG, msg, ...)
end
function log.info(msg, ...)
    log.record(log.INFO, msg, ...)
end
function log.error(msg, ...)
    log.record(log.ERR, msg, ...)
end
function log.flush()

end

return log