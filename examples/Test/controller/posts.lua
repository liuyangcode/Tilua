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
    local _, response = ctx:unpack()
    response.body = 'posts.index'
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