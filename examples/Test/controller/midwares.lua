local lw_util = require("Tilua.util")
local derive = require "Test.controller.base.rest".derive

local M = {
    table = 'midwares',
    view = 'midwares'
}
function M.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.midwares
    local midware = services:find(id)
    midware.config = lw_util.split(midware.config == ngx.null and "" or midware.config, ',')
    response:render('midwares/edit.html', midware)
end

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