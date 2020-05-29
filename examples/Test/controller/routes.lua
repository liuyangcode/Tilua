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

function routes.new(ctx)
    return ("routes/new.html")
end

function routes.show(ctx, id)
    ctx.response.body = ngx.re.gsub("32.254.48.88", "([\'\\\"])", "\\$1", "jo")
end

function routes.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.services
    response:render('routes/edit.html',services:find(id))
end

function routes.create(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local hosts = type(req.hosts) =='table' and table.concat(req.hosts,',') or req.hosts
    local paths = type(req.paths) =='table' and table.concat(req.paths,',') or req.paths
    local methods = type(req.methods) =='table' and table.concat(req.methods,',') or req.methods
    local protocols = type(req.protocols) =='table' and table.concat(req.protocols,',') or req.protocols



    local result = services:add({
        hosts = hosts or '',
        paths = paths or '/',
        methods = methods or '*',
        headers = req.headers or '',
        strip_path = req.strip_path or 0,
        preserve_host = req.preserve_host or 0,
        protocols = protocols or '*',
        created_at = {'exp','now()'},
        updated_at =  {'exp','now()'}
    })

    response.body = {
        code = result.affected_rows ==1 and 0 or -1,
        msg = "错误",
    }
end
function routes.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.services

    local result = services:where({id=id}):save({
        name = req.name,
        connect_timeout = req.name,
        path = req.path,
        host = req.host,
        port = req.port,
        protocol = req.protocol,
        read_timeout = req.read_timeout,
        write_timeout = req.write_timeout,
        connect_timeout = req.connect_timeout,
        updated_at =  {'exp','now()'}
    })
    response.body = {
        code =  result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end
function routes.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.routes
    local result = services:where({id=id}):delete()
    response.body = {
        code = result.affected_rows ==1 and 0 or -1,
        msg = '',
    }
end
return routes