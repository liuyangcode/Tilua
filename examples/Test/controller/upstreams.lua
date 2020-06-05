local lw_util = require("Tilua.util")

local upstreams = {}
---index
---@param ctx app
function upstreams.index(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    return {
        code = 0,
        count = ctx.model.upstreams:getField("count(1) as cnt"),
        data = ctx.model.upstreams:limit((page - 1) * limit, limit):select()
    }
end

function upstreams.new(ctx)
    return ("upstreams/new.html")
end

function upstreams.show(ctx, id)
end

function upstreams.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.upstreams
    response:render('upstreams/edit.html', services:find(id))
end

function upstreams.create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local services = ctx.model.upstreams
    local result = services:add({
        name = req.name,
        algorithm = req.algorithm,
        hash_on = req.hash_on,
        hash_on_header = req.hash_on_header,
        hash_on_cookie = req.hash_on_cookie,
        hash_fallback = req.hash_fallback,
        hash_fallback_header = req.hash_fallback_header,
        host_header = req.host_header,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    })
    return {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end

function upstreams.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.upstreams

    local result = services:where({ id = id }):save({
        weight = req.weight,
        host = req.host,
        port = req.port,
        upstreamid = req.upstreamid,
        updated_at = { 'exp', 'now()' }
    })
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end

function upstreams.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.upstreams
    local result = services:where({ id = id }):delete()
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end
return upstreams