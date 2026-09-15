package.path = "./?.lua;./?/init.lua;" .. (package.path or "")
if not ngx then
  _G.ngx = { md5=function(s) return s end, now=function() return 1 end, re={match=function() return nil end}, say=print }
end
package.preload["Tilua.utils.class"] = function()
  local M={}
  function M.define(parent)
    local c={__parent=parent}
    c.__index=c
    c.define=function() return M.define(c) end
    setmetatable(c,{__call=function(cls,...)
      local o=setmetatable({},c)
      if o._construct then o:_construct(...) end
      return o
    end})
    return c
  end
  return M
end
package.preload["Tilua.utils.util"] = function()
  local h=require("Tilua.core.helpers")
  return {
    choose=function(c,a,b) if c then return a else return b end end,
    empty=h.empty, is_array=h.is_array, is_string=h.is_string,
    is_scalar=function(v) local t=type(v) return t=="string" or t=="number" or t=="boolean" end,
    foreach=function(t,fn) for k,v in pairs(t or {}) do fn(v,k) end end,
    in_array=function(a,v) return h.find(a,v)~=nil end,
    addslashes=function(s) return (tostring(s):gsub("(['\"\\])","\\%1")) end,
    get_now_ms=function() return 0 end,
  }
end

local driver = require("Tilua.db.driver")
local d = driver({ type="mysql", hostname="127.0.0.1" }, {}, { debug=function() end, error=function() end })
local k = d:parseKey("user_id")
assert(k == "`user_id`", "backtick key got "..tostring(k))
local k2 = d:parseKey("u.name")
assert(k2:find("`") ~= nil, "dotted key")
local sql = d:parseSql("SELECT %FIELD% FROM %TABLE%", { table="users", field="id", where="", group="", having="", order="", limit="", union="", lock=false, comment="", force="", distinct=false, join="" })
assert(sql:find("users") or sql:find("`users`"), "table in sql: "..sql)
print("orm helpers tests passed")
