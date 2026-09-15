local Exception = {}
Exception.__index = Exception

function Exception.new(message, code, status, cause)
    return setmetatable({
        message = message or "Internal Server Error",
        code = code or "internal_error",
        status = status or 500,
        cause = cause,
    }, Exception)
end

function Exception.from(err, status)
    if Exception.is(err) then return err end
    return Exception.new(tostring(err), "internal_error", status or 500, err)
end

function Exception:__tostring()
    return self.message
end

function Exception.is(value)
    return type(value) == "table" and getmetatable(value) == Exception
end

function Exception.boundary(app, ctx, fn)
    local ok, result = xpcall(fn, debug.traceback)
    if ok then return result end

    local exception = Exception.from(result)
    local logger = app and app:get("logger")
    if logger and logger.error then
        logger:error("request failed: ", tostring(result))
    end

    if ctx and ctx.text then
        return ctx:text("Internal Server Error", exception.status)
    end
    return nil, exception
end

return Exception
