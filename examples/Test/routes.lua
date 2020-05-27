local route = require("Tilua.route")
route.prefix('/posts', {
    'json', 'body_parser'
})
route {
    ['=/api/v2'] = function(ctx)
        ---@type response
        local response = ctx.response
        response.body = { 1, 2, 3 }
    end
}
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
end, "[api]")
route.get('/test', function(ctx)
    local request, response = ctx:unpack()

    response.body = request.pid
end)
route.rest('/posts', 'controller.posts')

route.get('/user/login.html', function(ctx)
    local request, response = ctx:unpack()
    response:render('index/login.html')
end)

route.get('~/user/find/{uid}/{name}', function(ctx, uid, name)
    ctx.response.body = { uid, name, ctx.midware.test.config }
end, { { 'Test.midware.test', { a = 1, b = 1 } }, 'json', 'session' })

