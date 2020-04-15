local route = require("Tilua.route")

route.get('~^/user/get/{uid}', function(ctx, response, request, uid)
    --ctx.cache.test_redis:set('name',{
    --    name = name
    --},240)
    --response.body = ctx.cache.redis
    local user = ctx.model.user
    --user:where({
    --    uid = 1
    --})  :save({
    --    name = "刘洋2"
    --})

    response.body = user:cache(300):find(uid)
    return response
end, {
    before = "[api]"
})