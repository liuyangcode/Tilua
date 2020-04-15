local index = require("Tilua.controller").derive()

function index:_init(ctx)
    self:super(ctx)
end

function index:index(ctx,response,request)
    response.body = "hello world"
    return response
end

function index:login(ctx,response,request)
    response.body = self:display()
    return response
end
return index