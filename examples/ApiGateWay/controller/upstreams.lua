local M = {
    table = 'upstreams'
}
local derive = require "ApiGateWay.controller.base.rest".derive
local we = require "resty.worker.events"

function M.before_create(ctx)
    local req = ctx.request.body
    return {
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
    }
end

function M.after_create(ctx, insert_id, data)
    data.id = insert_id
    we.post('upstream', 'add', data)
end

function M.before_update(ctx, id)
    local req = ctx.request.body
    return {
        name = req.name,
        algorithm = req.algorithm,
        hash_on = req.hash_on,
        hash_on_header = req.hash_on_header,
        hash_on_cookie = req.hash_on_cookie,
        hash_fallback = req.hash_fallback,
        hash_fallback_header = req.hash_fallback_header,
        host_header = req.host_header,
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_update(ctx, id, data)
    data.id = id
    we.post('upstream', 'update', data, false)
end

function M.after_destory(ctx, id)
    we.post('upstream', 'delete', id, false)
end


return derive(M)