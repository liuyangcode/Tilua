--- Tilua.core.exception
--- Unified exception types + safe API error rendering.
---
--- API body shape (production-safe):
---   { "code": 500, "message": "Internal Server Error", "request_id": "..." }
---
--- Never leak stack traces, SQL, passwords, or filesystem paths in production.

local Exception = {}
Exception.__index = Exception

local LAYERS = {
    router     = true,
    controller = true,
    service    = true,
    database   = true,
    middleware = true,
    http       = true,
    app        = true,
}

local STATUS_MESSAGE = {
    [400] = "Bad Request",
    [401] = "Unauthorized",
    [403] = "Forbidden",
    [404] = "Not Found",
    [405] = "Method Not Allowed",
    [408] = "Request Timeout",
    [409] = "Conflict",
    [422] = "Unprocessable Entity",
    [429] = "Too Many Requests",
    [500] = "Internal Server Error",
    [501] = "Not Implemented",
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
}

-------------------------------------------------
-- Sensitive data scrubbing
-------------------------------------------------

local SENSITIVE_PATTERNS = {
    -- passwords / secrets in text
    { "([Pp]assword%s*[=:]%s*)[^%s,;\"']+", "%1***" },
    { "([Pp]wd%s*[=:]%s*)[^%s,;\"']+", "%1***" },
    { "([Ss]ecret%s*[=:]%s*)[^%s,;\"']+", "%1***" },
    { "([Tt]oken%s*[=:]%s*)[^%s,;\"']+", "%1***" },
    { "([Aa]pi[_%-]?[Kk]ey%s*[=:]%s*)[^%s,;\"']+", "%1***" },
    -- absolute paths (unix)
    { "(/[%w%._%-]+)+%.lua:?%d*", "[path]" },
    { "(/[%w%._%-]+)+%.sql", "[path]" },
    -- SQL fragments often contain schema noise; collapse long queries
    { "%f[%w](SELECT%s+.-%s+FROM%s+)", "SQL:" },
    { "%f[%w](INSERT%s+INTO%s+)", "SQL:" },
    { "%f[%w](UPDATE%s+)", "SQL:" },
    { "%f[%w](DELETE%s+FROM%s+)", "SQL:" },
}

function Exception.sanitize(msg)
    if msg == nil then
        return nil
    end
    msg = tostring(msg)
    for _, pair in ipairs(SENSITIVE_PATTERNS) do
        msg = msg:gsub(pair[1], pair[2])
    end
    -- truncate very long messages
    if #msg > 500 then
        msg = msg:sub(1, 500) .. "…"
    end
    return msg
end

function Exception.is_production(ctx)
    if ctx and ctx.config then
        local env = ctx.config.env or ctx.config.environment or ctx.status
        if env == "prod" or env == "production" then
            return true
        end
        if ctx.config.debug == false and (env == nil or env == "prod") then
            -- only treat as prod when explicitly not debug
            if ctx.config.app_env == "production" or ctx.debug == false then
                return true
            end
        end
        if ctx.config.debug == true or ctx.debug == true then
            return false
        end
        if env == "dev" or env == "development" or env == "test" then
            return false
        end
    end
    -- OpenResty: default safe if debug off
    if ctx and ctx.debug == false then
        return true
    end
    return false
end

-------------------------------------------------
-- Request ID
-------------------------------------------------

function Exception.request_id(ctx)
    if ctx and ctx.request_id then
        return ctx.request_id
    end
    if ngx and ngx.var and ngx.var.request_id and ngx.var.request_id ~= "" then
        return ngx.var.request_id
    end
    -- generate lightweight id
    local t = (ngx and ngx.now and ngx.now()) or os.clock()
    local pid = (ngx and ngx.worker and ngx.worker.pid and ngx.worker.pid()) or 0
    local id = string.format("%x-%x-%04x", math.floor(t * 1000), pid, math.random(0, 0xffff))
    if ctx then
        ctx.request_id = id
    end
    return id
end

-------------------------------------------------
-- Exception object
-------------------------------------------------

--- Create exception
--- @param opts table { layer, status, message, code, details, cause, public_message }
function Exception.new(opts)
    opts = opts or {}
    local status = tonumber(opts.status) or 500
    local layer = opts.layer or "app"
    if not LAYERS[layer] then
        layer = "app"
    end
    local obj = setmetatable({
        layer = layer,
        status = status,
        message = opts.message or STATUS_MESSAGE[status] or "Error",
        public_message = opts.public_message, -- safe for clients
        code = opts.code or (layer .. "_error"),
        details = opts.details,
        cause = opts.cause,
        stack = opts.stack,
        __tilua_error = true,
        __tilua_exception = true,
    }, Exception)
    return obj
end

function Exception:__tostring()
    return string.format("[%s] %s (%s)", self.layer, self.message, self.status)
end

function Exception.is(obj)
    return type(obj) == "table" and (obj.__tilua_exception or obj.__tilua_error)
end

-- Typed constructors
function Exception.router(msg, status, details)
    return Exception.new({ layer = "router", status = status or 404, message = msg, code = "router_error", details = details })
end

function Exception.controller(msg, status, details)
    return Exception.new({ layer = "controller", status = status or 500, message = msg, code = "controller_error", details = details })
end

function Exception.service(msg, status, details)
    return Exception.new({ layer = "service", status = status or 422, message = msg, code = "service_error", details = details })
end

function Exception.database(msg, status, details)
    return Exception.new({
        layer = "database",
        status = status or 500,
        message = msg,
        public_message = "Database error",
        code = "database_error",
        details = details,
    })
end

function Exception.middleware(msg, status, details)
    return Exception.new({ layer = "middleware", status = status or 500, message = msg, code = "middleware_error", details = details })
end

function Exception.http(status, msg, code)
    return Exception.new({ layer = "http", status = status or 500, message = msg, code = code or "http_error" })
end

--- Convert unknown error (string / table / exception) into Exception
function Exception.wrap(err, layer)
    if Exception.is(err) then
        if layer and not err.layer then
            err.layer = layer
        end
        return err
    end
    if type(err) == "number" then
        return Exception.new({ layer = layer or "http", status = err, message = STATUS_MESSAGE[err] })
    end
    local msg = type(err) == "table" and (err.message or err.msg or tostring(err)) or tostring(err)
    return Exception.new({
        layer = layer or "app",
        status = 500,
        message = msg,
        code = (layer or "app") .. "_error",
    })
end

--- From xpcall debug.traceback message
function Exception.from_xpcall(err_msg, layer)
    local msg = tostring(err_msg or "unknown error")
    local stack
    -- split message and stack if present
    local first = msg:match("([^\n]+)")
    if msg:find("\n") then
        stack = msg
        msg = first or msg
    end
    return Exception.new({
        layer = layer or "app",
        status = 500,
        message = msg,
        stack = stack,
        code = (layer or "app") .. "_error",
    })
end

-------------------------------------------------
-- Render
-------------------------------------------------

function Exception.public_payload(ex, ctx)
    local prod = Exception.is_production(ctx)
    local status = (ex and ex.status) or 500
    local rid = Exception.request_id(ctx)

    local message
    if prod then
        -- production: only public_message or generic status text
        if status >= 500 then
            message = (ex and ex.public_message) or STATUS_MESSAGE[status] or "Internal Server Error"
        else
            -- 4xx can show sanitized business message
            message = Exception.sanitize((ex and (ex.public_message or ex.message)) or STATUS_MESSAGE[status] or "Error")
        end
    else
        message = Exception.sanitize((ex and ex.message) or STATUS_MESSAGE[status] or "Error")
    end

    local body = {
        code = status,
        message = message,
        request_id = rid,
    }

    -- non-prod optional diagnostics (still sanitized)
    if not prod and ex then
        body.error_code = ex.code
        body.layer = ex.layer
        if ex.details ~= nil then
            body.details = ex.details
        end
        -- never attach full stack to JSON even in dev by default; log it instead
    end

    return body, status, rid
end

function Exception.render(response, ex, ctx)
    ctx = ctx or (response and response.ctx)
    local body, status, rid = Exception.public_payload(ex, ctx)
    if response then
        response.status = status
        response.headers = response.headers or {}
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        if rid then
            response.headers["X-Request-Id"] = rid
        end
        local ok, cjson = pcall(require, "cjson.safe")
        if not ok then
            ok, cjson = pcall(require, "cjson")
        end
        if ok and cjson and cjson.encode then
            response.body = cjson.encode(body)
        else
            response.body = string.format(
                '{"code":%d,"message":%q,"request_id":%q}',
                body.code, body.message, body.request_id or ""
            )
        end
    end
    return response, body
end

--- Log exception server-side (full detail), never send to client in prod
function Exception.log(ctx, ex)
    local logger = ctx and ctx.logger
    local line = string.format(
        "exception layer=%s status=%s code=%s msg=%s rid=%s",
        tostring(ex and ex.layer),
        tostring(ex and ex.status),
        tostring(ex and ex.code),
        Exception.sanitize(ex and ex.message),
        Exception.request_id(ctx)
    )
    if logger and logger.error then
        logger:error(line)
        if ex and ex.stack and not Exception.is_production(ctx) then
            logger:error(ex.stack)
        elseif ex and ex.stack and logger.debug then
            -- in prod still keep stack only at debug if logger supports it
            pcall(function()
                logger:debug(ex.stack)
            end)
        end
    elseif ngx then
        ngx.log(ngx.ERR, line)
    end
end

--- xpcall handler factory
function Exception.handler(layer)
    return function(err)
        return Exception.from_xpcall(err, layer)
    end
end

--- Protect a function; on failure return Exception object
function Exception.protect(layer, fn, ...)
    local ok, a, b, c, d = xpcall(function(...)
        return fn(...)
    end, Exception.handler(layer), ...)
    if ok then
        return a, b, c, d
    end
    return a -- Exception
end

--- Throw (error) an exception object for xpcall to catch
function Exception.throw(ex)
    error(ex, 0)
end

return Exception
