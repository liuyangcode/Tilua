--- Tilua.log
--- Application logger.
---
--- Wiring: `Tilua.logging.writer` provides the output backends (file / ngx /
--- stderr).  Historically this module tried to require `Tilua.log.<type>`,
--- a directory that does not exist, so `log.handler` was permanently nil and
--- every log line was buffered into memory and never written.  The writer is
--- the supported backend now; `Tilua.log.<type>` is still honoured first so
--- an application can still supply its own backend.
---
---   logger:debug/info/warn/error/notice(...)
---   logger:record(level, ...)
---   logger:context(level, ctx, ...)   -- adds trace_id when available
---   logger:flush()                    -- write buffered lines

local import = require("Tilua.utils.util").import

---@class log
local log = {
    STDERR = "STDERR",
    EMERG  = "EMERG",
    ALERT  = "ALERT",
    CRIT   = "CRIT",
    ERR    = "ERR",
    ERROR  = "ERR",
    WARN   = "WARN",
    NOTICE = "NOTICE",
    INFO   = "INFO",
    DEBUG  = "DEBUG",
    NONE   = "NONE",
}

--- Severity ordering, so `level = "WARN"` means "WARN and above".
local SEVERITY = {
    DEBUG  = 10,
    INFO   = 20,
    NOTICE = 30,
    WARN   = 40,
    ERR    = 50,
    CRIT   = 60,
    ALERT  = 70,
    EMERG  = 80,
    NONE   = 100,
}

local function severity_of(level)
    return SEVERITY[level] or 0
end

local mt = { __index = log }

--- Configured minimum severity (numeric).
local function threshold(self)
    if self._threshold == nil then
        self._threshold = severity_of(self.config.level or "INFO")
    end
    return self._threshold
end

local function enrich_message(context, args)
    if not context then
        return args
    end
    local trace_id
    if type(context) == "table" then
        trace_id = context.trace_id
        if not trace_id and context.trace then
            trace_id = context.trace.trace_id
        end
        if not trace_id and context.request_id then
            trace_id = context.request_id
        end
    end
    if trace_id then
        table.insert(args, 1, "[trace_id=" .. tostring(trace_id) .. "]")
    end
    return args
end

local function format_line(level, msg)
    local stamp = (ngx and ngx.localtime and ngx.localtime()) or os.date("%Y-%m-%d %H:%M:%S")
    return string.format("[%s] [%s] %s", stamp, level, msg)
end

--- Should this level be emitted at all?
function log:enabled(level)
    return severity_of(level) >= threshold(self)
end

function log:record(level, ...)
    level = level or ""
    if level == log.NONE or level == "" then
        return true
    end
    if not self:enabled(level) then
        return true
    end

    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring((select(i, ...)))
    end
    local line = format_line(level, table.concat(parts, " "))

    local handler = self.handler
    if not handler then
        -- Never lose the message silently: fall back to ngx or stderr.
        if ngx and ngx.log then
            ngx.log(ngx[level] or ngx.INFO, line)
        else
            io.stderr:write(line, "\n")
        end
        return true
    end

    if type(handler.write_line) == "function" then
        handler:write_line(line, level)
    elseif type(handler.record) == "function" then
        handler:record(level, line)
    else
        self.log_data[#self.log_data + 1] = { level = level, msg = line }
    end
    return true
end

function log:debug(...)  self:record(log.DEBUG, ...) end
function log:info(...)   self:record(log.INFO, ...) end
function log:notice(...) self:record(log.NOTICE, ...) end
function log:warn(...)   self:record(log.WARN, ...) end
function log:error(...)  self:record(log.ERR, ...) end

--- Structured, context-aware logging.
function log:context(level, context, ...)
    local args = enrich_message(context, { ... })
    self:record(level, table.concat(args, " "))
end

function log:write(...)
    self:record("", ...)
end

function log:flush()
    local handler = self.handler
    if handler and type(handler.flush) == "function" then
        return handler:flush()
    end
    return true
end

function log:close()
    local handler = self.handler
    if handler and type(handler.close) == "function" then
        return handler:close()
    end
    return true
end

--- Build a logger bound to `cfg`.
function log.new(cfg)
    cfg = cfg or {}
    local self = setmetatable({
        log_data    = {},
        config      = cfg,
        _threshold  = nil,
        handler     = nil,
    }, mt)

    -- 1. application-supplied backend: Tilua.log.<type>
    local custom
    if type(cfg.type) == "string" and cfg.type ~= "" then
        custom = import("Tilua.log." .. cfg.type)
    end

    if custom then
        if type(custom.init) == "function" then
            pcall(custom.init, cfg)
        end
        self.handler = custom
    else
        -- 2. built-in writer backends (file / ngx / stderr)
        local ok, writer = pcall(require, "Tilua.logging.writer")
        if ok and writer and writer.create then
            self.handler = writer.create(cfg)
        end
    end

    return self
end

--- Kept for backwards compatibility: returns the logger *class*.
function log.init(cfg)
    return log
end

--- Convenience: build a ready-to-use logger.
function log.create(cfg)
    return log.new(cfg)
end

return log
