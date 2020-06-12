local lw_util = require("Tilua.util")

local midwares = {}
---index
---@param ctx app
function midwares.index(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    return {
        code = 0,
        count = ctx.model.midwares:getField("count(1) as cnt"),
        data = ctx.model.midwares:limit((page - 1) * limit, limit):select()
    }
end

function midwares.new(ctx)
    return ("midwares/new.html")
end

function midwares.show(ctx, id)
end

function midwares.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.midwares
    local midware = services:find(id)
    midware.config = lw_util.split(midware.config == ngx.null and "" or midware.config,',')
    response:render('midwares/edit.html', midware)
end

function midwares.create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local services = ctx.model.midwares
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config
    local result = services:add({
        name = req.name,
        package = req.package,
        alias = req.alias,
        config = configs,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' },
        status = 1
    })
    return {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end

function midwares.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.midwares
    local configs = type(req.config) == 'table' and table.concat(req.config, ',') or req.config

    local result = services:where({ id = id }):save({
        name = req.name,
        package = req.package,
        alias = req.alias,
        config = configs or "",
        updated_at = { 'exp', 'now()' },
        status = 1
    })
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end

function midwares.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.midwares
    local result = services:where({ id = id }):delete()
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end
return midwares