local index = require("Tilua.controller").derive()
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
    return 'services/index.html'
end
function index:routes(ctx)
    return 'routes/index.html'
end
function index:targets(ctx)
    return 'targets/index.html'
end
function index:baffle(ctx)
    return 'baffle/index.html'
end
function index:midwares(ctx)
    return 'midwares/index.html'
end
function index:upstreams(ctx)
    return 'upstreams/index.html'
end
function index:secrets(ctx)
    return 'secrets/index.html'
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