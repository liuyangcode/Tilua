local M = {}

function M.run()
    local ok, ctx = pcall(require, "Tilua.context")
    if not ok then
        return false, "context module unavailable"
    end
    return ctx ~= nil
end

return M
