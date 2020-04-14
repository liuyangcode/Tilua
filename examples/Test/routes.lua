local route = require("Tilua.route")
route.get('/', function(ctx, response, request, name)
    return 'Hello,World'
end)

route.get('~/{name}', function(ctx, response, request, name)
    ctx.cache.set('name',{
        name = name
    },240)
    --response.body = ctx.cache.redis
    local user = ctx.model('user')
    response.body = user:find(1)
    return response
end, {
    before = "[api]"
})