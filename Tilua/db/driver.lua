--- Shim: Tilua.db.driver – Query-backed base for legacy define()
local Query = require("Tilua.database.query")
local class = require("Tilua.utils.class")
local driver = class.define()
function driver:properties()
    self.config, self.logger, self.ctx = {}, nil, nil
    self.queryStr, self.modelSql, self.lastInsID = "", {}, nil
    self.numRows, self.transTimes, self.error = 0, 0, ""
    self.linkID, self._linkID, self.model = {}, nil, nil
    self.queryTimes, self.executeTimes = 0, 0
    self._q = Query.new({})
end
function driver:_construct(config, context, logger)
    self:properties()
    if config then for k, v in pairs(config) do self.config[k] = v end end
    self.logger, self.ctx = logger, context
    self._q = Query.new({ like_fields = self.config.db_like_fields })
end
function driver:parseKey(k) return self._q:key(k) end
function driver:parseValue(v) return self._q:value(v) end
function driver:escapeString(s) return self._q.escape(s) end
function driver:parseField(f) return self._q:field(f) end
function driver:parseTable(t) return self._q:table_name(t) end
function driver:parseWhere(w) return self._q:where(w) end
function driver:parseOrder(o) return self._q:order(o) end
function driver:parseLimit(l) return self._q:limit(l) end
function driver:buildSelectSql(options) return self._q:build_select(options) end
function driver:parseSet(data) return self._q:set_clause(data) end
function driver:connect() end
function driver:query() end
function driver:execute() end
function driver:close() end
return driver
