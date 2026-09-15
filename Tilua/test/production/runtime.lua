local M = {}

function M.run()
    local ok = true

    local app = package.loaded["Tilua.app"]
    if app and app.runtime_status and app.runtime_status ~= "READY" then
        ok = false
    end

    return ok
end

return M
