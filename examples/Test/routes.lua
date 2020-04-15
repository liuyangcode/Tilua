local route = require("Tilua.route")

route.get('~/user/get/{uid}', function(ctx, response, request, uid)
    local user = ctx.model.user
    local data = user:save({
        name = "刘洋2"
    },{
        where = {
            uid = {'eq',uid}
        },
        limit = 1
    })
    response.body = user:getLastSql()
    return response
end, {
    before = "[api]"
})