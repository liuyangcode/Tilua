local M = {}

-- CLI smoke test entry.
-- This test verifies that the CLI module can be loaded.
function M.run()
    local ok = pcall(require, "cli.main")
    return ok
end

return M
