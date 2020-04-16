local index = require("Tilua.controller").derive()
local lw_util = require("Tilua.util")
function index:_init(ctx)
    self:super(ctx)
end

function index:index(ctx, response, request)
    response.body = "hello world"
    return response
end

function index:login(ctx, response, request)
    response.body = self:display()
    return response
end

function index:upload(ctx, response, request)
    if request.method == 'POST' then
        response.body = ''
    else
        response.body = self:display()

    end
    return response
end
return index