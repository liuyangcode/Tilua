local index = require("Tilua.controller").derive()
local lw_util = require("Tilua.util")
function index:_init(ctx)
    self:super(ctx)
end
---index
---@param ctx app
function index:index(ctx)
    local request, response = ctx:unpack()
    --request.body = {
    --    c=1
    --}
    --request.body.a = 1
    response.body = ctx.midware.mvc.controller_name
end

function index:login()
    self:display()
end

---upload
---@param ctx app
function index:upload(ctx)
    local request, response = ctx:unpack()
    if request.method == 'POST' then
        response.body = request.body
    else
        self:display()
    end
end
return index