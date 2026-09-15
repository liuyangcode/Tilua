local M = {}

function M.run()
    local ok, health = pcall(require, "Tilua.health")
    if not ok then
        return false
    end

    if health.check then
        local result = health.check()
        return result ~= nil
    end

    return true
end

return M
