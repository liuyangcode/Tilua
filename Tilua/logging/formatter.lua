--- Tilua.logging.formatter
--- Formats log records as text or JSON (structured).

local Formatter = {}

local LEVEL_NAME = {
    STDERR = "STDERR",
    EMERG = "EMERG",
    ALERT = "ALERT",
    CRIT = "CRIT",
    ERR = "ERROR",
    ERROR = "ERROR",
    WARN = "WARN",
    WARNING = "WARN",
    NOTICE = "NOTICE",
    INFO = "INFO",
    DEBUG = "DEBUG",
}

local function iso_time()
    if ngx and ngx.utctime then
        -- ngx.utctime -> "YYYY-MM-DD HH:MM:SS"
        local t = ngx.utctime()
        return (t:gsub(" ", "T")) .. "Z"
    end
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function encode_json(tbl)
    local ok, cjson = pcall(require, "cjson.safe")
    if not ok then
        ok, cjson = pcall(require, "cjson")
    end
    if ok and cjson and cjson.encode then
        local s = cjson.encode(tbl)
        if s then
            return s
        end
    end
    -- minimal fallback
    local parts = {}
    for k, v in pairs(tbl) do
        parts[#parts + 1] = string.format("%q:%q", tostring(k), tostring(v))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Build a structured record table
function Formatter.record(level, message, fields)
    local name = LEVEL_NAME[level] or LEVEL_NAME[string.upper(tostring(level or "INFO"))] or "INFO"
    local rec = {
        ts = iso_time(),
        level = name,
        msg = message ~= nil and tostring(message) or "",
    }
    if type(fields) == "table" then
        for k, v in pairs(fields) do
            if k ~= "ts" and k ~= "level" and k ~= "msg" then
                rec[k] = v
            end
        end
    end
    return rec
end

--- JSON line (structured logging)
function Formatter.json(level, message, fields)
    return encode_json(Formatter.record(level, message, fields))
end

--- Human-readable text line
function Formatter.text(level, message, fields)
    local name = LEVEL_NAME[level] or tostring(level or "INFO")
    local base = string.format("[%s] %s", name, message ~= nil and tostring(message) or "")
    if type(fields) ~= "table" or not next(fields) then
        return base
    end
    local parts = {}
    -- stable-ish order: request_id, trace_id first
    local prefer = { "request_id", "trace_id", "span_id" }
    local seen = {}
    for _, k in ipairs(prefer) do
        if fields[k] ~= nil then
            parts[#parts + 1] = k .. "=" .. tostring(fields[k])
            seen[k] = true
        end
    end
    for k, v in pairs(fields) do
        if not seen[k] then
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return base .. " " .. table.concat(parts, " ")
end

--- Format according to config.format = "json" | "text"
function Formatter.format(config, level, message, fields)
    local fmt = (config and config.format) or "text"
    if fmt == "json" then
        return Formatter.json(level, message, fields)
    end
    return Formatter.text(level, message, fields)
end

return Formatter
