local we = require "resty.worker.events"
local uuid = require("Tilua.utils.util").uuid
local CreateUUID = require("Tilua.utils.util").random_string
local derive = require "Test.controller.base.rest".derive

local M = {
    table = 'secrets'
}

function M.before_create(ctx)
    local request, _ = ctx:unpack()
    local req = request.body
    if req.accessKey ~= '' and ctx.model.secrets:where({ accessKey = req.accessKey }):find() then
        return nil, req.accessKey .. "已被占用，请重试！"
    end
    return {
        name = req.name,
        accessKey = req.accessKey == '' and CreateUUID() or req.accessKey,
        secretKey = req.secretKey == '' and uuid() or req.secretKey,
        status = 1,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    }
end

function M.before_update(ctx)
    local req = ctx.request.body
    return {
        name = req.name,
        status = req.status,
        updated_at = { 'exp', 'now()' }
    }
end

return derive(M)