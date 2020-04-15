local user = require("Tilua.controller")

function user:_init()

end

function user:index(ctx,response,request)
    response.body = "hello world"
    return response
end

return user