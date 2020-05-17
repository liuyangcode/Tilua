local index = require("Tilua.controller").derive()
local lw_util = require("Tilua.util")
function index:_init(ctx)
    self:super(ctx)
end
---index
---@param ctx app
function index:index(ctx)
    self:assign('url', ctx.request.body.url or "/index/services")
    self:display()
end

function index:services(ctx)
    self:display()
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