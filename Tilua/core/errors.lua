--- Tilua.core.errors
--- Structured error helpers for consistent HTTP error responses.

local M = {}

local ERROR_MAP = {
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
    [502] = "Bad Gateway",
    [503] = "Service Unavailable",
}

---@class TiluaError
---@field status number
---@field message string
---@field code string|nil
---@field details any

--- Create a structured error object
---@param status number HTTP status
---@param message string|nil
---@param code string|nil machine-readable code
---@param details any|nil
---@return TiluaError
function M.new(status, message, code, details)
    status = status or 500
    return {
        status  = status,
        message = message or ERROR_MAP[status] or "Error",
        code    = code,
        details = details,
        __tilua_error = true,
    }
end

function M.is_error(obj)
    return type(obj) == "table" and obj.__tilua_error == true
end

function M.bad_request(msg, code, details)
    return M.new(400, msg, code or "bad_request", details)
end

function M.unauthorized(msg, code)
    return M.new(401, msg or "Unauthorized", code or "unauthorized")
end

function M.forbidden(msg, code)
    return M.new(403, msg or "Forbidden", code or "forbidden")
end

function M.not_found(msg, code)
    return M.new(404, msg or "Not Found", code or "not_found")
end

function M.method_not_allowed(msg)
    return M.new(405, msg or "Method Not Allowed", "method_not_allowed")
end

function M.conflict(msg, code)
    return M.new(409, msg or "Conflict", code or "conflict")
end

function M.too_many(msg)
    return M.new(429, msg or "Too Many Requests", "rate_limited")
end

function M.internal(msg, details)
    return M.new(500, msg or "Internal Server Error", "internal_error", details)
end

--- Apply error to response object
---@param response table Tilua response
---@param err TiluaError|number|string
---@param as_json boolean|nil
function M.apply(response, err, as_json)
    if type(err) == "number" then
        err = M.new(err)
    elseif type(err) == "string" then
        err = M.new(500, err)
    elseif not M.is_error(err) then
        err = M.internal(tostring(err))
    end

    response.status = err.status

    if as_json then
        response.headers = response.headers or {}
        response.headers["Content-Type"] = "application/json; charset=utf-8"
        local body = {
            error = {
                status  = err.status,
                message = err.message,
                code    = err.code,
            }
        }
        if err.details ~= nil then
            body.error.details = err.details
        end
        local ok, encoded = pcall(require("cjson.safe").encode, body)
        response.body = ok and encoded or ('{"error":{"status":' .. err.status .. ',"message":"' .. err.message .. '"}}')
    else
        response.body = err.message
    end

    return response
end

--- Safe pcall wrapper that converts failures into TiluaError
function M.protect(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then
        return a, b, c, d
    end
    return M.internal(tostring(a))
end

return M
