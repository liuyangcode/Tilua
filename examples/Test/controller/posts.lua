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

end

function posts.show(ctx, id)
    local _, response = ctx:unpack()
    response.body = 'posts.show'..id
end

function posts.edit(ctx, id)

end

function posts.create(ctx)

end
function posts.update(ctx, id)

end
function posts.destroy(ctx, id)

end
return posts