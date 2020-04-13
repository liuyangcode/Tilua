local route = require("Tilua.route")

route.get('/', function(ctx, response, request, name)
    return 'Hello,World'
end)

route.get('~/{name}', function(ctx, response, request, name)
    response.body = 'Hello,' .. ctx:C('db_type')
    return response
end,{
    beforemidware = 'Test.midware.test'
})