--- Tilua.http.cookie
--- Shared cookie build / parse helpers (RFC 6265 oriented)

local ngx = ngx
local type = type
local format = string.format
local concat = table.concat

local M = {}

--- URL-encode cookie value (conservative)
function M.encode_value(v)
    if v == nil then
        return ""
    end
    v = tostring(v)
    -- encode characters that are unsafe in cookie-octet
    return (v:gsub("([^%w%-%_%.%~])", function(c)
        return format("%%%02X", string.byte(c))
    end))
end

function M.decode_value(v)
    if not v or v == "" then
        return v
    end
    v = v:gsub("%+", " ")
    return (v:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

--- Parse Cookie request header into name->value map
function M.parse(header)
    local jar = {}
    if not header or header == "" then
        return jar
    end
    for part in string.gmatch(header, "[^;]+") do
        local name, value = part:match("^%s*([^=]+)%s*=%s*(.*)%s*$")
        if name and name ~= "" then
            name = name:match("^%s*(.-)%s*$")
            value = value or ""
            -- strip optional quotes
            value = value:match('^"(.*)"$') or value
            jar[name] = M.decode_value(value)
        end
    end
    return jar
end

--[[
  opts = {
    name, value,
    path = "/",
    domain = nil,
    max_age = nil,          -- seconds (preferred)
    expires = nil,          -- absolute unix time OR seconds-from-now if expires_in style
    expires_in = nil,       -- seconds from now (alias)
    httponly = true,
    secure = false,
    samesite = "Lax",       -- Lax | Strict | None
    raw = false,            -- if true, do not encode value
  }
]]
function M.build(opts)
    if type(opts) == "string" then
        -- already a full Set-Cookie line
        return opts
    end
    if type(opts) ~= "table" or not opts.name then
        return nil
    end

    local name = tostring(opts.name)
    local value = opts.value
    if value == nil then
        value = ""
    else
        value = tostring(value)
    end
    if not opts.raw then
        value = M.encode_value(value)
    end

    local parts = { name .. "=" .. value }

    local path = opts.path or "/"
    parts[#parts + 1] = "Path=" .. path

    if opts.domain and opts.domain ~= "" then
        parts[#parts + 1] = "Domain=" .. opts.domain
    end

    local max_age = opts.max_age
    if max_age == nil and opts.expires_in ~= nil then
        max_age = tonumber(opts.expires_in)
    end
    -- legacy: expires as relative seconds (old Tilua API)
    if max_age == nil and opts.expires ~= nil then
        local e = tonumber(opts.expires)
        if e and e > 0 and e < 1e10 then
            -- treat as relative seconds if small enough
            max_age = e
        end
    end

    if max_age ~= nil then
        max_age = tonumber(max_age) or 0
        parts[#parts + 1] = "Max-Age=" .. tostring(max_age)
        if max_age > 0 then
            parts[#parts + 1] = "Expires=" .. ngx.cookie_time(ngx.time() + max_age)
        elseif max_age <= 0 then
            -- delete cookie
            parts[#parts + 1] = "Expires=" .. ngx.cookie_time(0)
        end
    elseif opts.expires and type(opts.expires) == "number" and opts.expires > 1e10 then
        -- absolute unix timestamp
        parts[#parts + 1] = "Expires=" .. ngx.cookie_time(opts.expires)
    end

    -- httponly: explicit true adds flag; nil does not force (caller decides)
    if opts.httponly then
        parts[#parts + 1] = "HttpOnly"
    end

    if opts.secure then
        parts[#parts + 1] = "Secure"
    end

    local ss = opts.samesite or opts.same_site or opts.SameSite
    if ss and ss ~= "" then
        ss = tostring(ss)
        -- normalize
        local lower = ss:lower()
        if lower == "none" then
            ss = "None"
            -- SameSite=None requires Secure
            local has_secure = opts.secure
            if not has_secure then
                parts[#parts + 1] = "Secure"
            end
        elseif lower == "strict" then
            ss = "Strict"
        else
            ss = "Lax"
        end
        parts[#parts + 1] = "SameSite=" .. ss
    end

    return concat(parts, "; ")
end

--- Build a deletion Set-Cookie
function M.build_clear(name, opts)
    opts = opts or {}
    return M.build({
        name = name,
        value = "",
        path = opts.path or "/",
        domain = opts.domain,
        max_age = 0,
        httponly = opts.httponly ~= false,
        secure = opts.secure,
        samesite = opts.samesite or opts.same_site or "Lax",
        raw = true,
    })
end

return M
