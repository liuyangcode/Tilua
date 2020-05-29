local ApiGateWay = require("Tilua.app").derive()

ApiGateWay.name = "ApiGateWay"
ApiGateWay.path = "/usr/local/openresty/lua/ApiGateWay/"
ApiGateWay.debug = true
ApiGateWay.status = 'dev'

function ApiGateWay:_init()
    self:super(self)
end
function ApiGateWay.on_app_init(ctx)
    ctx.logger:debug("on_app_init --- ",ctx.name)
    ngx.var.upstream_scheme = 'http'
    ngx.var.upstream_uri = ctx.request.path_info
    ngx.var.upstream_connection = ctx.request.header.connection or ''
    ngx.var.upstream_host = "32.254.48.89"

end

function ApiGateWay.balancer()
    local ctx = ngx.ctx.ctx
    ctx.logger:debug("ApiGateWay.balancer")
    ctx:dispatch()
    --ngx.var.upstream_scheme = 'http'
    --ngx.var.upstream_uri = ctx.request.path_info
    --ngx.var.upstream_connection = ctx.request.header.connection or ''
    --ngx.var.upstream_host = "32.254.48.89"

end

function ApiGateWay.log(ApiGateWay)
    ApiGateWay.request_end()
end

return ApiGateWay