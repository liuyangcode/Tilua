local ApiGateWay = require("Tilua.app").derive()
local lw_utils = require("Tilua.util")
local split = require("pl.utils").split
ApiGateWay.name = "ApiGateWay"
ApiGateWay.path = "/usr/local/openresty/lua/ApiGateWay/"
ApiGateWay.debug = true
ApiGateWay.status = 'dev'

function ApiGateWay:_init()
    self:super(self)
end

function ApiGateWay.on_startup(ctx)
    local ngx = ngx
    local context = {
        config = ctx
    }
    local localtime = ngx.localtime
    local logger = ApiGateWay.get_logger(context)
    logger:write("\n[", localtime(), "]", "ApiGateWay Worker init success worker pid ", ngx.worker.pid())
    logger:flush()
end

---on_app_init
---@param ctx app
function ApiGateWay.on_app_init(ctx)
    ctx.logger:debug("on_app_init --- ", ctx.name)
    if not ApiGateWay.is_routes_loaded then
        local routes = ctx.model.routes:select()
        lw_utils.foreach(routes, function(route)
            local methods = split(route.methods, ',', true)
            local paths = split(route.paths, ',', true)
            lw_utils.foreach(methods, function(verb)
                lw_utils.foreach(paths, function(path)
                    ApiGateWay.route.add_route_rule(
                            ctx.name,
                            verb,
                            '*',
                            path,
                            {
                                {
                                    responser = route.service,
                                    midware = {},
                                    route = route
                                },
                                {}
                            }
                    )
                end)
            end)
        end)
        ApiGateWay.is_routes_loaded = true
    end
    ctx:dispatch(ctx.route.run(ctx))

    ngx.var.upstream_scheme = 'http'
    ngx.var.upstream_uri = ctx.request.path_info
    ngx.var.upstream_connection = ctx.request.header.connection or ''
    ngx.var.upstream_host = "32.254.48.89"
end

function ApiGateWay.on_app_end(ctx)

end
function ApiGateWay.balancer()
    local ctx = ngx.ctx
    local app = ctx.ctx
    app.logger:debug("ApiGateWay.balancer")
    local balancer = require("ngx.balancer")
    local host = ctx.peer.host
    local port = ctx.peer.port

    local state, code = balancer.get_last_failure()

    app.logger:debug("balancer.get_last_failure", state, code)
    local ok, err = balancer.set_current_peer(host, port)
    balancer.set_timeouts(10, 10, 10)
end

function ApiGateWay.log(ApiGateWay)
    ApiGateWay.request_end()
end

return ApiGateWay