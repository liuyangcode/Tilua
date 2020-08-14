local lw_util = require("Tilua.utils.util")
local derive = require "ApiGateWay.controller.base.rest".derive

local M = {
    table = 'midwares'
}

function M.before_create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config

    return {
        name = req.name,
        package = req.package,
        alias = req.alias,
        config = configs,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' },
        status = 1
    }
end

function M.before_update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config

    return {
        name = req.name,
        package = req.package,
        alias = req.alias,
        config = configs or "",
        updated_at = { 'exp', 'now()' },
        status = 1
    }
end
return derive(M)