local lw_util = require("Tilua.utils.util")
local derive = require "Test.controller.base.rest".derive

local M = {
    table = 'baffle',
    view = 'baffle'
}
function M.show(ctx, id)
    local services = ctx.model.baffle
    local b = services:find(id)
    return 'baffle/show.html', b
end

function M.before_create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local headers = {}
    if type(req.header) ~= 'table' then
        req.header = { req.header }
    end
    for _, v in ipairs(req.header) do
        table.insert(headers, lw_util.parse_expression(v, ';', ':'))
    end

    return {
        name = req.name,
        header = lw_util.json_encode(headers),
        body = req.body,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' },
        status = 1
    }
end
function M.before_update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local headers = {}
    if type(req.header) ~= 'table' then
        req.header = { req.header }
    end
    for _, v in ipairs(req.header) do
        table.insert(headers, lw_util.parse_expression(v, ';', ':'))
    end

    return {
        name = req.name,
        header = lw_util.json_encode(headers),
        body = req.body,
        updated_at = { 'exp', 'now()' }
    }
end
return derive(M)