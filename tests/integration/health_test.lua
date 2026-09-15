-- Tilua Health API Integration Test
local M = {}

function M.run()
    local ok, health = pcall(require, "Tilua.health")
    assert(ok, "health module load failed")
    assert(health ~= nil, "health unavailable")
    return true
end

return M
