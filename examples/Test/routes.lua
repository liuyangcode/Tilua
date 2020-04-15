local route = require("Tilua.route")
route.get('/', function(ctx, response, request, name)
    return 'Hello,World'
end)

route.get('~/{name}', function(ctx, response, request, name)
    --ctx.cache.test_redis:set('name',{
    --    name = name
    --},240)
    --response.body = ctx.cache.redis
    local user = ctx.model.user
    user:where({
        uid = 1
    })  :save({
        name = "刘洋2"
    })

    response.body = user:cache(300):find(1)
    return response
end, {
    before = "[api]"
})