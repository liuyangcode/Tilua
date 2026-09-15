--- Router index / match unit test without OpenResty regex (mock ngx.re)
if not ngx then
    _G.ngx = {
        re = {
            match = function(s, pattern, opt)
                -- very small subset for test: treat pattern as plain if no special
                if pattern == s then
                    return { s }
                end
                return nil
            end,
            sub = function(s, pattern, repl)
                return s
            end,
            gsub = function(s, pattern, repl)
                return s:gsub("%s+", " ")
            end,
        },
        var = {},
    }
end

package.path = "./?.lua;./?/init.lua;" .. (package.path or "")

-- stubs
package.preload["Tilua.core.helpers"] = function()
    local M = {}
    function M.strip(s)
        if type(s) ~= "string" then return s end
        return (s:match("^%s*(.-)%s*$"))
    end
    function M.split(str, sep, plain)
        sep = sep or "%s+"
        plain = plain == true
        local t, from = {}, 1
        local d1, d2 = string.find(str, sep, from, plain)
        while d1 do
            t[#t+1] = string.sub(str, from, d1-1)
            from = d2 + 1
            d1, d2 = string.find(str, sep, from, plain)
        end
        t[#t+1] = string.sub(str, from)
        return t
    end
    function M.find(t, v)
        for i, x in ipairs(t or {}) do if x == v then return i end end
    end
    function M.sub(t, i, j)
        local r = {}
        for k = i, j or #t do r[#r+1] = t[k] end
        return r
    end
    function M.insertvalues(dst, src)
        for _, v in ipairs(src or {}) do dst[#dst+1] = v end
        return dst
    end
    function M.deepcopy(t)
        local r = {}
        for k, v in pairs(t) do r[k] = type(v) == "table" and M.deepcopy(v) or v end
        return r
    end
    return M
end

package.preload["Tilua.utils.util"] = function()
    return {
        extend = function(a, b) for k, v in pairs(b or {}) do a[k] = v end end,
        is_string = function(v) return type(v) == "string" end,
        is_array = function(t) return type(t) == "table" end,
        callable = function(f) return type(f) == "function" end,
        foreach = function(t, fn) for k, v in pairs(t) do fn(v, k) end end,
        parse_expression = function() return {} end,
        combine = function(keys, values)
            local r = {}
            for i, k in ipairs(keys or {}) do r[k] = values and values[i] end
            return r
        end,
        index_value = function() return nil end,
    }
end

package.preload["Tilua.middleware"] = function()
    return { parse = function(x) return type(x) == "table" and x or {} end }
end

local route = require("Tilua.http.router")

local function assert_true(c, msg)
    if not c then error(msg or "assert failed") end
end

route.set_app_name("app")
-- inject compiled rules directly
route.rule_caches.app = {
    {
        matcher = "=",
        path = "/health",
        method = { "get" },
        responser = function() return "ok" end,
        midware = {},
    },
    {
        matcher = "*",
        path = "/api",
        method = { "get", "post" },
        responser = "api@index",
        midware = {},
    },
    {
        matcher = "=",
        path = "/users",
        method = { "*" },
        responser = "users@list",
        midware = {},
    },
}
route.rebuild_index("app")

local idx = route.indexes.app
assert_true(idx.exact["get"]["/health"] ~= nil, "exact get /health indexed")
assert_true(idx.exact["*"]["/users"] ~= nil, "exact * /users")
assert_true(#idx.prefix["get"] >= 1, "prefix get")

local matched = route.find_matched_route("app", "GET", "/health")
assert_true(#matched >= 1 and matched[1].path == "/health", "match health")

matched = route.find_matched_route("app", "post", "/api/v1")
assert_true(#matched >= 1, "prefix /api matches /api/v1")

local ctx = {
    name = "app",
    request = { method = "get", path_info = "/health" },
    logger = { debug = function() end },
}
local ok, rule = route.run(ctx)
assert_true(ok and rule.path == "/health", "run exact")

-- second hit uses best_match cache
ok, rule = route.run(ctx)
assert_true(ok and rule.path == "/health", "cached run")

print("router index tests passed")
