local index = require("Tilua.controller").derive()
local lw_util = require("Tilua.util")
local manager = require("Tilua.cache.manager")
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
function index:routes(ctx)
    self:display()
end
function index:targets(ctx)
    self:display()
end
function index:baffle(ctx)
    self:display()
end
function index:midwares(ctx)
    self:display()
end
function index:upstreams(ctx)
    self:display()
end
function index:login()
    self:display()
end
function index:test(ctx)
    ---@type model
    local routes = ctx.model.routes
    ctx.response.body = routes:select({
        cache = {}
    })
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