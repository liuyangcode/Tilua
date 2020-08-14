local M = {
    table = 'targets'
}
local derive = require "ApiGateWay.controller.base.rest".derive
local we = require "resty.worker.events"

function M.before_create(ctx)
    local req = ctx.request.body
    return {
        host = req.host,
        port = req.port,
        weight = req.weight,
        upstreamid = req.upstreamid,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_create(ctx, insert_id, data)
    data.id = insert_id
    we.post('target', 'add', data, false)
end

function M.before_update(ctx, id)
    local req = ctx.request.body
    return {
        weight = req.weight,
        host = req.host,
        port = req.port,
        upstreamid = req.upstreamid,
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_update(ctx, id, data)
    data.id = id
    we.post('target', 'update', data, false)
end

function M.after_destory(ctx, id)
    we.post('target', 'delete', id, true)
end

return derive(M)