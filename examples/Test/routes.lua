local route = require("Tilua.route")

route.get('~/user/get/{uid}', function(ctx, uid)
    local user = ctx.model.user
    local data = user:save({
        name = "刘洋2"
    }, {
        where = {
            uid = { 'eq', uid }
        },
        limit = 1
    })
    ctx.response.body = user:getLastSql()
end, {
    before = "[api]"
})

route.rest('/posts','controller.posts')
route.get('/user/login.html', function(ctx)
    local request, response = ctx:unpack()
    response:render('index/login.html')
end)

route.get('~/user/find/{uid}', function(ctx, uid)
    ctx.response.body = uid
end)