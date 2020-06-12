local ApiGateWay = require("Tilua.app").derive()
local lw_utils = require("Tilua.util")
local split = require("pl.utils").split
local route_service = require("ApiGateWay.routes")
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
            local validations = {
            }
            if route.hosts ~= '' then
                validations['request.host'] = {
                    'IN',
                    split(route.hosts, ',')
                }
            end
            if route.headers ~= '' then
                local headers = lw_utils.parse_expression(route.headers)
                for k, v in pairs(headers) do
                    validations['request.header.' .. k] = {
                        'EQ',
                        v
                    }
                end
            end
            ctx.logger:debug("upstream uri ", lw_utils.json_encode(validations))

            local methods = split(route.methods, ',', true)
            local paths = split(route.paths, ',', true)
            lw_utils.foreach(methods, function(verb)
                lw_utils.foreach(paths, function(path)
                    ApiGateWay.route.add_route_rule(
                            ctx.name,
                            string.lower(verb),
                            '*',
                            path,
                            {
                                {
                                    responser = {
                                        type = route.proxy_type,
                                        serviceid = route.serviceid
                                    },
                                    midware = route_service.get_midwares(ctx, route.id),
                                    path = path,
                                    route = route
                                },
                                validations
                            }
                    )
                end)
            end)
        end)
        ApiGateWay.is_routes_loaded = true
    end
end

function ApiGateWay.access(ApiGateWay)

end

function ApiGateWay.rewrite(ApiGateWay)
    local ctx = ApiGateWay:init()
    local cache_key = ctx.request.method .. ":" .. ctx.request.uri .. ":" .. ctx.request.host
    local router

    if ctx.cache.exists(cache_key) and not ctx.debug then
        router = ctx.cache.get(cache_key)
    else
        router = ctx.route.run(ctx)
        ctx.cache.set(cache_key, router)
    end
    ctx:dispatch({
        proxy = router[1], params = router[2], midware = router[3], router = router[4]
    })
end

function ApiGateWay.on_app_end(ctx)

end
function ApiGateWay.balancer()
    local ctx = ngx.ctx
    local peer = ctx.peer
    local app = ctx.ctx
    app.logger:debug("ApiGateWay.balancer")
    local balancer = require("ngx.balancer")
    local host = peer.host
    local port = peer.port
    local state, code = balancer.get_last_failure()
    app.logger:debug("balancer.get_last_failure", state, code)
    local ok, err = balancer.set_current_peer(host, port)
    if not ok then
        app.logger:error("failed to set the current peer (address: ",
                tostring(host), " port: ", tostring(port),
                "): ", tostring(err))
        return ngx.exit(500)
    end
    ok, err = balancer.set_timeouts(peer.connect_timeout / 1000, peer.send_timeout / 1000, peer.read_timeout / 1000)
    if not ok then
        app.logger:error("could not set upstream timeouts: ", err)
    end
end

function ApiGateWay.log(ApiGateWay)
    ApiGateWay.request_end()
end

return ApiGateWay