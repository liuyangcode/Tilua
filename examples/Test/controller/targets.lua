local we = require "resty.worker.events"

local targets = {}
---index
---@param ctx app
function targets.index(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    return {
        code = 0,
        count = ctx.model.targets:getField("count(1) as cnt"),
        data = ctx.model.targets:limit((page - 1) * limit, limit):select()
    }
end

function targets.new(ctx)
    return ("targets/new.html")
end

function targets.show(ctx, id)
end

function targets.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.targets
    response:render('targets/edit.html', services:find(id))
end

function targets.create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    local services = ctx.model.targets
    local data = {
        host = req.host,
        port = req.port,
        weight = req.weight,
        upstreamid = req.upstreamid,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    }
    local result = services:add(data)
    ctx.logger:debug(require("Tilua.util").json_encode(result))

    if result.affected_rows == 1 then
        data.id = result.insert_id
        we.post('target', 'add', data, true)
    end
    return {
        code = result.affected_rows == 1 and 0 or -1,
        msg = "错误",
    }
end

function targets.update(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.targets
    local data = {
        weight = req.weight,
        host = req.host,
        port = req.port,
        upstreamid = req.upstreamid,
        updated_at = { 'exp', 'now()' }
    }
    local result = services:where({ id = id }):save(data)
    if result.affected_rows == 1 then
        data.id = id
        we.post('target', 'update', data, true)
    end
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = id,
    }
end

function targets.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.targets
    local result = services:where({ id = id }):delete()
    if result.affected_rows == 1 then
        we.post('target', 'delete', id, true)
    end
    response.body = {
        code = result.affected_rows == 1 and 0 or -1,
        msg = '',
    }
end
return targets