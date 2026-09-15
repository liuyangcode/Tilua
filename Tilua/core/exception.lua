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
    if type(err) == "table" and getmetatable(err) == Exception then
        return err
    end
    return Exception.new(tostring(err), "internal_error", status or 500, err)
end

function Exception:__tostring()
    return self.message
end

function Exception.is(value)
    return type(value) == "table" and getmetatable(value) == Exception
end

function ExceptionBoundary(app)
    return function(ctx)
        local ok, result = xpcall(function()
            return app:dispatch(ctx)
        end, debug.traceback)
        if ok then
            return result
        end

        local exception = Exception.from(result)
        if app.logger and app.logger.error then
            app.logger:error("request failed: ", tostring(result))
        end
        if ctx and ctx.response and ctx.text then
            return ctx:text("Internal Server Error", exception.status)
        end
        return nil, exception
    end
end

return Exception
