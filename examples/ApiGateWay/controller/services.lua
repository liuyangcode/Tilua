--GET	/posts	posts	app.controllers.posts.index
--GET	/posts/new	new_post	app.controllers.posts.new
--GET	/posts/:id	post	app.controllers.posts.show
--GET	/posts/:id/edit	edit_post	app.controllers.posts.edit
--POST	/posts	posts	app.controllers.posts.create
--PUT	/posts/:id	post	app.controllers.posts.update
--DELETE	/posts/:id	post	app.controllers.posts.destroy
local M = {
    table = 'services'
}
local derive = require "ApiGateWay.controller.base.rest".derive

local we = require "resty.worker.events"

function M.before_create(ctx)
    local req = ctx.request.body
    return {
        name = req.name,
        connect_timeout = req.name,
        path = req.path or "/",
        host = req.host,
        port = req.port,
        protocol = req.protocol,
        read_timeout = req.read_timeout,
        write_timeout = req.write_timeout,
        connect_timeout = req.connect_timeout,
        created_at = { 'exp', 'now()' },
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_create(ctx, insert_id, data)
    data.id = insert_id
    we.post('service', 'add', data)
end

function M.before_update(ctx, id)
    local req = ctx.request.body
    return {
        name = req.name,
        connect_timeout = req.name,
        path = req.path,
        host = req.host,
        port = req.port,
        protocol = req.protocol,
        read_timeout = req.read_timeout,
        write_timeout = req.write_timeout,
        connect_timeout = req.connect_timeout,
        updated_at = { 'exp', 'now()' }
    }
end

function M.after_update(ctx, id, data)
    data.id = id
    we.post('service', 'update', data, true)
end
function M.after_destory(ctx, id)
    we.post('service', 'delete', id, true)
end
return derive(M)