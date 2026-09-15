if not ngx then
    _G.ngx = {
        time = os.time,
        cookie_time = function(t)
            return "Thu, 01 Jan 1970 00:00:00 GMT"
        end,
    }
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

local cookie = require("Tilua.http.cookie")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed") end
end

local line = cookie.build({
    name = "sid",
    value = "abc123",
    path = "/",
    max_age = 3600,
    httponly = true,
    secure = true,
    samesite = "Lax",
    raw = true,
})
assert_true(line:find("sid=abc123", 1, true), "name=value")
assert_true(line:find("HttpOnly", 1, true), "HttpOnly")
assert_true(line:find("Secure", 1, true), "Secure")
assert_true(line:find("SameSite=Lax", 1, true), "SameSite")
assert_true(line:find("Max-Age=3600", 1, true), "Max-Age")

local none = cookie.build({ name = "x", value = "1", samesite = "None", raw = true })
assert_true(none:find("SameSite=None", 1, true) and none:find("Secure", 1, true), "None implies Secure")

local cleared = cookie.build_clear("sid", { path = "/" })
assert_true(cleared:find("Max-Age=0", 1, true), "clear max-age 0")

local jar = cookie.parse('a=1; b="hello%20w"; c=3')
assert_true(jar.a == "1", "parse a")
assert_true(jar.c == "3", "parse c")

local enc = cookie.encode_value("a b=c")
assert_true(enc:find("%%") ~= nil or enc ~= "a b=c", "encoded")

print("cookie tests passed")
