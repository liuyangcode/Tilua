local route = require("Tilua.route")
route.prefix('/posts', {
    'json', 'body_parser'
})
route.prefix('/routes', {
    'json', 'body_parser'
})
route {
    ['=/api/v2'] = function(ctx)
        ---@type response
        local response = ctx.response
        response.body = { 1, 2, 3 }
    end
}


route.rest('/posts', 'controller.posts')
route.rest('/routes', 'controller.routes')

route.get('/user/login.html', function(ctx)
    local request, response = ctx:unpack()
    response:render('index/login.html')
end)

route.get('~/user/find/{uid}/{name}', function(ctx, uid, name)
    ctx.response.body = { uid, name, ctx.midware.test.config }
end, { { 'Test.midware.test', { a = 1, b = 1 } }, 'json', 'session' })

