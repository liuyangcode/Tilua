--GET	/posts	posts	app.controllers.posts.index
--GET	/posts/new	new_post	app.controllers.posts.new
--GET	/posts/:id	post	app.controllers.posts.show
--GET	/posts/:id/edit	edit_post	app.controllers.posts.edit
--POST	/posts	posts	app.controllers.posts.create
--PUT	/posts/:id	post	app.controllers.posts.update
--DELETE	/posts/:id	post	app.controllers.posts.destroy
local posts = {}

---index
---@param ctx app
function posts.index(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local page = req.page or 1
    local limit = req.limit or 10
    response.body = {
        code = 0,
        count = ctx.model.services:getField("count(1) as cnt"),
        data = ctx.model.services:limit((page - 1) * limit, limit):select()
    }
end

function posts.new(ctx)
    ctx.response.render("posts/new.html")
end

function posts.show(ctx, id)
    ctx.response.body = ngx.re.gsub("32.254.48.88", "([\'\\\"])", "\\$1", "jo")
end

function posts.edit(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.services
    response.render('posts/edit.html',services:find(id))
end

function posts.create(ctx)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.services
    local result = services:add({
        name = req.name,
        connect_timeout = req.name,
        path = req.path,
        host = req.host,
        port = req.port,
        protocol = req.protocol,
        read_timeout = req.read_timeout,
        write_timeout = req.write_timeout,
        connect_timeout = req.connect_timeout,
        created_at = {'exp','now()'},
        updated_at =  {'exp','now()'}
    })
    response.body = {
        code = result.affected_rows ==1 and 0 or -1,
        msg = "错误",
    }
end
function posts.update(ctx, id)
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
function posts.destroy(ctx, id)
    local request, response = ctx:unpack()
    local req = request.body
    local services = ctx.model.services
    local result = services:where({id=id}):delete()
    response.body = {
        code = result.affected_rows ==1 and 0 or -1,
        msg = '',
    }
end
return posts