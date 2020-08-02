local lw_util = require("Tilua.util")
local derive = require "Test.controller.base.rest".derive
local we = require "resty.worker.events"

local M = {
    table = 'routes',
    view = 'routes'
}
function M.add_plugin(ctx)
    local plugins = ctx.model.midwares:where({ status = 1 }):select()
    return 'routes/add_plugin.html', { id = ctx.request.body.id, objecttype = ctx.request.body.objecttype, plugins = plugins }
end
function M.do_add_plugin(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config

    local services = ctx.model.plugins

    local result = services:add({
        objectid = req.objectid,
        objecttype = req.objecttype,
        phase = req.phase,
        mid = req.mid,
        status = 1,
        config = configs,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    })
    if result.affected_rows == 1 then
        we.post('route', 'add_plugin', req.routeid, true)
    end
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end
function M.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local route = services:find(id)
    route.hosts = lw_util.split(route.hosts, ',', true)
    route.paths = lw_util.split(route.paths, ',', true)

    response:render('routes/edit.html', route)
end

function M.before_create(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local hosts = type(req.hosts) == 'table' and table.concat(req.hosts, ',') or req.hosts
    local paths = type(req.paths) == 'table' and table.concat(req.paths, ',') or req.paths
    local methods = type(req.methods) == 'table' and table.concat(req.methods, ',') or req.methods
    local protocols = type(req.protocols) == 'table' and table.concat(req.protocols, ',') or req.protocols
    return {
        hosts = hosts or '',
        paths = paths or '/',
        methods = methods or '*',
        headers = req.headers or '',
        strip_path = req.strip_path == 'on' and 0 or 1,
        preserve_host = req.preserve_host == 'on' and 1 or 0,
        serviceid = req.serviceid or 0,
        proxy_type = req.proxy_type or 'proxy',
        path_handle = req.path_handle or 'v0',
        protocols = protocols or '*',
        validations = req.validations,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_create(ctx, insert_id, data)
    data.id = insert_id
    we.post('route', 'add', data)
end

function M.before_update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local hosts = type(req.hosts) == 'table' and table.concat(req.hosts, ',') or req.hosts
    local paths = type(req.paths) == 'table' and table.concat(req.paths, ',') or req.paths
    local methods = type(req.methods) == 'table' and table.concat(req.methods, ',') or req.methods
    local protocols = type(req.protocols) == 'table' and table.concat(req.protocols, ',') or req.protocols
    return {
        hosts = hosts or '',
        paths = paths or '/',
        methods = methods or '*',
        headers = req.headers or '',
        strip_path = req.strip_path == 'on' and 0 or 1,
        preserve_host = req.preserve_host == 'on' and 1 or 0,
        serviceid = req.serviceid or 0,
        proxy_type = req.proxy_type or 'proxy',
        path_handle = req.path_handle or 'v0',
        protocols = protocols or '*',
        updated_at = { 'exp', 'now()' },
        validations = req.validations
    }
end

function M.after_update(ctx, id, data)
    data.id = id
    we.post('route', 'update', data)
end

return derive(M)