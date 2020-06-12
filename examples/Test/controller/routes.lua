local lw_util = require("Tilua.util")

local routes = {}
---index
---@param ctx app
function routes.index(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    return {
        code = 0,
        count = ctx.model.routes:getField("count(1) as cnt"),
        data = ctx.model.routes:limit((page - 1) * limit, limit):select()
    }
end
function routes.add_plugin(ctx)
    local plugins = ctx.model.midwares:where({ status = 1 }):select()
    return 'routes/add_plugin.html', { id = ctx.request.body.id, plugins = plugins }
end
function routes.do_add_plugin(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config

    local services = ctx.model.routes_plugins

    local result = services:add({
        routeid = req.routeid,
        mid = req.mid,
        status = 1,
        config = configs,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    })
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end
function routes.new(ctx)
    return ("routes/new.html")
end

function routes.show(ctx, id)
    ctx.response.body = ngx.re.gsub("32.254.48.88", "([\'\\\"])", "\\$1", "jo")
end

function routes.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local route = services:find(id)
    route.hosts = lw_util.split(route.hosts, ',', true)
    route.paths = lw_util.split(route.paths, ',', true)

    response:render('routes/edit.html', route)
end

function routes.create(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local hosts = type(req.hosts) == 'table' and table.concat(req.hosts, ',') or req.hosts
    local paths = type(req.paths) == 'table' and table.concat(req.paths, ',') or req.paths
    local methods = type(req.methods) == 'table' and table.concat(req.methods, ',') or req.methods
    local protocols = type(req.protocols) == 'table' and table.concat(req.protocols, ',') or req.protocols

    local result = services:add({
        hosts = hosts or '',
        paths = paths or '/',
        methods = methods or '*',
        headers = req.headers or '',
        strip_path = req.strip_path == 'on' and 0 or 1,
        preserve_host = req.preserve_host or 0,
        serviceid = req.serviceid or 0,
        proxy_type = req.proxy_type or 'proxy',
        path_handle = req.path_handle or 'v0',
        protocols = protocols or '*',
        validations = req.validations,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    })

    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end
function routes.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local hosts = type(req.hosts) == 'table' and table.concat(req.hosts, ',') or req.hosts
    local paths = type(req.paths) == 'table' and table.concat(req.paths, ',') or req.paths
    local methods = type(req.methods) == 'table' and table.concat(req.methods, ',') or req.methods
    local protocols = type(req.protocols) == 'table' and table.concat(req.protocols, ',') or req.protocols

    local result = services:where({ id = id }):save({
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
        updated_at = { 'exp', 'now()' }
    })
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end
function routes.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local result = services:where({ id = id }):delete()
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end
return routes