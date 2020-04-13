

local route = require("Tilua.route")


route.get('/', function(request)
    return 'Hello,World'
end)