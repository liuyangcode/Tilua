local class = require("Tilua.utils.class")

---@class metrics_collector
local collector = class.define()

function collector:_construct()
    self.counters = {}
    self.histograms = {}
    self.active = 0
end

function collector:counter(name, value)
    value = value or 1
    self.counters[name] = (self.counters[name] or 0) + value
end

function collector:histogram(name, value)
    self.histograms[name] = self.histograms[name] or {}
    table.insert(self.histograms[name], value)
end

function collector:start_request()
    self.active = self.active + 1
    self:counter("tilua_http_requests_total")
    return ngx.now()
end

function collector:end_request(start_time, failed)
    self.active = math.max(0, self.active - 1)
    self:histogram("tilua_http_request_duration_seconds", ngx.now() - start_time)
    if failed then
        self:counter("tilua_errors_total")
    end
end

function collector:export()
    local result = {}
    for k, v in pairs(self.counters) do
        result[#result + 1] = k .. " " .. v
    end
    result[#result + 1] = "tilua_active_requests " .. self.active
    return table.concat(result, "\n")
end

return collector
