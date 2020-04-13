local route = require("Tilua.route")
local midware = require("Tilua.midware")
route.get('/', function(ctx, response, request, name)
    return 'Hello,World'
end)

route.get('~/{name}', function(ctx, response, request, name)
    response.body = midware.is_group("[api")
    return response
end)