--- JSON response middleware.
---
--- NOTE: this required `Tilua.midware.base`, which does not exist — only the
--- `Tilua.midware` *module shim* does (Tilua/midware.lua), not the `.base`
--- submodule.  Every other middleware had already been migrated to
--- `Tilua.middleware.base`; this one was missed, so any app using the default
--- `api` / `web` middleware groups (Tilua/config/default.lua) crashed on boot
--- with "module 'Tilua.midware.base' not found".
local base = require("Tilua.middleware.base")
local json_response = (type(base.define) == "function" and base.define()) or base

local json_encode = require("Tilua.utils.util").json_encode

function json_response:handle(next, ...)
    local response = next(...)
    if type(response.body) == 'table' then
        response:add_header('content_type', "application/json;charset=utf-8")
        response.body = json_encode(response.body) or response.body
    end
    return response
end

return json_response