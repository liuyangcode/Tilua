-- Tilua Logger Unit Test
local M = {}

function M.run()
    local ok, logger = pcall(require, "Tilua.log")
    assert(ok, "logger module load failed")
    assert(logger ~= nil, "logger unavailable")
    return true
end

return M
