local M = {}

function M.run()
    local ok, metrics = pcall(require, "Tilua.metrics")
    if not ok then
        return false, "metrics module unavailable"
    end
    return metrics ~= nil
end

return M
