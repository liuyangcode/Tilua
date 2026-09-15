local M = {}

function M.run()
    local ok = pcall(function()
        error("production exception test")
    end)

    if ok then
        return false, "exception boundary failed"
    end

    return true
end

return M
