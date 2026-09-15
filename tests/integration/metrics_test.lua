-- Tilua Metrics API Integration Test
local M = {}

function M.run()
    local ok, metrics = pcall(require, "Tilua.metrics")
    assert(ok, "metrics module load failed")
    assert(metrics ~= nil, "metrics unavailable")
    return true
end

return M
