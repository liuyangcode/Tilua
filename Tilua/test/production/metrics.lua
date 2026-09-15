local M = {}

function M.run()
    local ok, metrics = pcall(require, "Tilua.metrics.exporter")
    if not ok or not metrics then
        return false, "metrics exporter unavailable"
    end

    if type(metrics.prometheus) ~= "function" then
        return false, "prometheus exporter missing"
    end

    return true
end

return M
