

---@class log
local log = {}
local ngx = ngx
local ngx_log = ngx.log

log.STDERR = ngx.STDERR
log.EMERG = ngx.EMERG
log.ALERT = ngx.ALERT
log.CRIT = ngx.CRIT
log.ERR = ngx.ERR
log.WARN = ngx.WARN
log.NOTICE = ngx.NOTICE
log.INFO = ngx.INFO
log.DEBUG = ngx.DEBUG

function log.record(level, ...)
    ngx_log(level, ...)
end

return log
