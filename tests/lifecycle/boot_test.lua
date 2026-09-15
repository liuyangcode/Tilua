-- Tilua Runtime Boot Lifecycle Test
local M = {}

function M.run()
    local ok, app = pcall(require, "Tilua.app")
    assert(ok, "application boot module load failed")
    assert(app ~= nil, "application unavailable")
    return true
end

return M
