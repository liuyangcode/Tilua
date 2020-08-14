local controller = require("Tilua.controller")
local index = controller()
---index
---@param ctx app
function index:index(ctx)
    local menu = {
        {
            title = '服务管理',
            items = {
                {
                    title = "服务列表",
                    link = "/?url=/index/services"
                },
                {
                    title = "挡板资源",
                    link = "/?url=/index/baffle"
                }
            },
            tag = 'service'
        },
        {
            title = 'Api管理',
            items = {
                {
                    title = "路由列表",
                    link = "/?url=/index/routes"
                },
                {
                    title = "秘钥管理",
                    link = "/?url=/index/secrets"
                }
            },
            tag = 'api'
        },
        {
            title = '负载管理',
            items = {
                {
                    title = "负载列表",
                    link = "/?url=/index/upstreams"
                },
                {
                    title = "节点列表",
                    link = "/?url=/index/targets"
                }
            },
            tag = 'upstream'
        },
        {
            title = '证书管理',
            items = {
                {
                    title = "证书列表",
                    link = "/?url=/index/certificate"
                }
            },
            tag = 'certificate'
        },
        {
            title = '安全管理',
            items = {
                {
                    title = "黑白名单",
                    link = "/?url=/index/certificate"
                }
            },
            tag = 'secure'
        },
        {
            title = '插件管理',
            items = {
                {
                    title = "生命周期插件",
                    link = "/?url=/index/lifetime"
                },
                {
                    title = "插件列表",
                    link = "/?url=/index/midwares"
                }
            },
            tag = 'midwares'
        },
        {
            title = '日志管理',
            items = {
                {
                    title = "访问日志",
                    link = "/?url=/index/accesslogs"
                },
                {
                    title = "阻断日志",
                    link = "/?url=/index/blockuplogs"
                },
                {
                    title = "操作日志",
                    link = "/?url=/index/oplogs"
                },
                {
                    title = "登录日志",
                    link = "/?url=/index/loginlogs"
                }
            },
            tag = 'logs'
        },
    }
    self:assign('url', ctx.request.body.url or "/index/services")
    self:assign('tag',ctx.request.body.tag or 'service')
    self:assign('menu',menu)
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
function index:certificate(ctx)
    return 'certificate/index.html'
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