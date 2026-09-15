local M = {}

function M.run()
    local stages = {
        "CREATED",
        "RUNNING",
        "RELEASED"
    }

    for _, stage in ipairs(stages) do
        if not stage then
            return false, "lifecycle stage invalid"
        end
    end

    return true
end

return M
