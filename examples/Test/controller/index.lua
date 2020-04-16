local index = require("Tilua.controller").derive()
local lw_util = require("Tilua.util")
function index:_init(ctx)
    self:super(ctx)
end

function index:index(ctx)
    ctx.response.body = "hello world"
    return ctx.response
end

function index:login(ctx)
    self:display()
end

---upload
---@param ctx app
function index:upload(ctx)
    local request, response = ctx:unpack()
    if request.method == 'POST' then
        response.body = ''
    else
        self:display()
    end
end
return index