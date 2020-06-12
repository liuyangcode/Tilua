local lw_util = require("Tilua.util")

local baffle = {}
---index
---@param ctx app
function baffle.index(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    return {
        code = 0,
        count = ctx.model.baffle:getField("count(1) as cnt"),
        data = ctx.model.baffle:limit((page - 1) * limit, limit):select()
    }
end

function baffle.new(ctx)
    return ("baffle/new.html")
end

function baffle.show(ctx, id)
    local services = ctx.model.baffle
    local b = services:find(id)
    return 'baffle/show.html',b
end

function baffle.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.baffle
    local b = services:find(id)
    response:render('baffle/edit.html', b)
end

function baffle.create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local services = ctx.model.baffle
    local headers = {}
    if type(req.header) ~= 'table' then
        req.header  = { req.header }
    end
    for _, v in ipairs(req.header) do
        table.insert(headers, lw_util.parse_expression(v, ';', ':'))
    end
    local result = services:add({
        name = req.name,
        header = lw_util.json_encode(headers),
        body = req.body,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' },
        status = 1
    })

    return {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end

function baffle.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.baffle
    local headers = {}
    if type(req.header) ~= 'table' then
        req.header  = { req.header }
    end
    for _, v in ipairs(req.header) do
        table.insert(headers, lw_util.parse_expression(v, ';', ':'))
    end
    local result = services:where({ id = id }):save({
        name = req.name,
        header = lw_util.json_encode(headers),
        body = req.body,
        updated_at = { 'exp', 'now()' }
    })
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end

function baffle.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.baffle
    local result = services:where({ id = id }):delete()
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end
return baffle