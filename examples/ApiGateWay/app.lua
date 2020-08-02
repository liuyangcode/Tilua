local ApiGateWay = require("Tilua.app").derive()
local lw_utils = require("Tilua.util")
local route_service = require("ApiGateWay.routes")
local balancer = require("ngx.balancer")
local plugins = require("ApiGateWay.plugins")

local balancer_service = require("ApiGateWay.balancer")
ApiGateWay.name = "ApiGateWay"
ApiGateWay.path = "/usr/local/openresty/lua/ApiGateWay/"
ApiGateWay.debug = true
ApiGateWay.status = 'dev'
function ApiGateWay:_init()
    self:super(self)
end
function ApiGateWay.init_worker()
    --local healthcheck = require("resty.healthcheck")
    --
    local we = require "resty.worker.events"
    local ok, err = we.configure({
        shm = "events", -- defined by "lua_shared_dict"
        timeout = 2,            -- life time of unique event data in shm
        interval = 1,           -- poll interval (seconds)

        wait_interval = 0.010,  -- wait before retry fetching event data
        wait_max = 0.5,         -- max wait time before discarding event
        shm_retries = 999,      -- retries for shm fragmentation (no memory)
    })
    if not ok then
        ngx.log(ngx.ERR, "failed to configure worker events: ", err)
        return
    end
    we.register(balancer_service.ev_handler)

end
function ApiGateWay:on_body_filter()
    self.logger:debug("on_body_filter ", self.name)
end

function ApiGateWay:on_header_filter()
    self.logger:debug("on_header_filter ", self.name)
end


function ApiGateWay.on_startup(ctx)
    local ngx = ngx
    local context = {
        config = ctx
    }
    local localtime = ngx.localtime
    local logger = ApiGateWay.init_logger(context)
    require("ApiGateWay.balancer").init()
    logger:write("\n[", localtime(), "]", "ApiGateWay Worker init success worker pid ", ngx.worker.pid())
    logger:flush()
end

---on_app_init
---@param ctx app
function ApiGateWay.on_app_init(ctx)
    ctx.logger:debug("on_app_init --- ", ctx.name)
    route_service.load(ctx)
end

function ApiGateWay.access(ApiGateWay)
    local ctx = ngx.ctx.ctx
    local ak = ctx.request.args.accessToken or ctx.request.header.accessToken
    local midwares
    if ak then
        midwares = plugins.get_secret_midwares(ctx, 'access', ak)
    end
    ctx.dispatcher:make_chain_call(midwares, ctx.route.run, ctx)

    local handler = ctx.dispatcher:create_responser({
        ctx.route.run, { ctx }, midwares or {}
    })
    local response = ctx.dispatcher:prepare_response(handler())
    if response.status ~= 0 and response.status ~= 200 then
        response:send()
    else
        local router = response.body
        response.body = nil
        ctx:dispatch({
            proxy = router[1], params = router[2], midware = router[3], router = router[4]
        })
    end
end

function ApiGateWay.rewrite(ApiGateWay)
    lw_utils.elapse_time_start("BALANCER_START")
    ApiGateWay:init()

end

function ApiGateWay.on_app_end(ctx)

end
function ApiGateWay.balancer()
    local ctx = ngx.ctx
    local peer = ctx.peer
    local app = ctx.ctx

    local host = peer.host
    local port = peer.port
    --local state, code = balancer.get_last_failure()
    app.logger:debug("set the current peer (address: ",
            tostring(host), " port: ", tostring(port),
            "): ")
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
    app.response.headers['BALANCER_LATENCY'] = lw_utils.get_now_ms() - lw_utils.elapse_time_start("BALANCER_START")
    app.response:send_headers(true)
end

function ApiGateWay.log(ApiGateWay)
    ApiGateWay.request_end()
end

return ApiGateWay