--- API shape tests (no OpenResty required for pure helpers)
if not ngx then
    _G.ngx = {
        status = 0,
        headers_sent = false,
        time = os.time,
        cookie_time = function() return "Thu, 01 Jan 1970 00:00:00 GMT" end,
        print = function() end,
        exit = function(s) return s end,
        redirect = function() end,
        var = {},
        req = { get_headers = function() return {} end, get_uri_args = function() return {} end },
        resp = {},
        worker = { pid = function() return 1 end },
        localtime = function() return "2026-01-01" end,
    }
    package.preload["ngx.resp"] = function()
        return { add_header = function() end }
    end
    package.preload["cjson.safe"] = function()
        return {
            encode = function(t)
                if type(t) == "table" then return '{"ok":true}' end
                return tostring(t)
            end,
            decode = function() return {} end,
        }
    end
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

-- minimal class
package.preload["Tilua.utils.class"] = function()
    local M = {}
    function M.define()
        local c = {}
        c.__index = c
        setmetatable(c, {
            __call = function(cls, ...)
                local obj = setmetatable({}, cls)
                if obj._construct then obj:_construct(...) end
                return obj
            end,
        })
        return c
    end
    return M
end

local response = require("Tilua.http.response")
local cookie = require("Tilua.http.cookie")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed") end
end

local resp = response({ config = { default_content_type = "text/html", default_charset = "utf-8" } })
resp:json({ ok = true }, 200)
assert_true(resp.status == 200, "status 200")
assert_true(type(resp._body) == "string", "json body")
assert_true(resp.headers["Content-Type"]:find("json") ~= nil, "json ct")

resp:set_cookie({ name = "a", value = "1", httponly = true, samesite = "Lax", raw = true })
assert_true(type(resp.headers["Set-Cookie"]) == "table", "set-cookie list")
assert_true(#resp.headers["Set-Cookie"] >= 1, "cookie added")

resp:clear_cookie("a")
assert_true(#resp.headers["Set-Cookie"] >= 2, "clear added")

resp:text("hi")
assert_true(resp.headers["Content-Type"]:find("text/plain") ~= nil)

resp:attachment("report.pdf", "application/pdf")
assert_true(resp.headers["Content-Disposition"]:find("attachment") ~= nil)

print("request/response api tests passed")
