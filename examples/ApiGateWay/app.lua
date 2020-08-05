local ApiGateWay = require("Tilua.app").derive()
local lw_utils = require("Tilua.utils.util")
local route_service = require("ApiGateWay.service.routes")
local balancer = require("ngx.balancer")
local plugins = require("ApiGateWay.service.plugins")

local ssl_certificate = require("ApiGateWay.service.certificate")
local load_cert_and_key = ssl_certificate.load_cert_and_key


local pl_utils = require("pl.utils")
local ngx_ssl = require "ngx.ssl"
local server_name = ngx_ssl.server_name
local clear_certs = ngx_ssl.clear_certs
local parse_pem_cert = ngx_ssl.parse_pem_cert
local parse_pem_priv_key = ngx_ssl.parse_pem_priv_key
local set_cert = ngx_ssl.set_cert
local set_priv_key = ngx_ssl.set_priv_key




local balancer_service = require("ApiGateWay.balancer")
ApiGateWay.name = "ApiGateWay"
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



function ApiGateWay.ssl_certificate()
    local sn, err = server_name()
    if err then
        ngx.log(ERR, "could not get server name ", err)
        return ngx.exit(ngx.ERROR)
    end

    ngx.log(ngx.ERR,"ApiGateWay.ssl_certificate")
    local cert_and_key,err = ssl_certificate.find_key_and_cert(sn)
    if not cert_and_key then
        ngx.log(ngx.ERR, err)
        return ngx.exit(500)
    end

    local ok, err = clear_certs()
    if not ok then
        ngx.log(ngx.ERR, "could not clear existing (default) certificates: ", err)
        return ngx.exit(500)
    end

    ok, err = set_cert(cert_and_key.cert)
    if not ok then
        ngx.log(ngx.ERR, "could not set configured certificate: ", err)
        return ngx.exit(500)
    end

    ok, err = set_priv_key(cert_and_key.key)
    if not ok then
        ngx.log(ngx.ERR, "could not set configured private key: ", err)
        return ngx.exit(500)
    end
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
end

function ApiGateWay.access(ApiGateWay)
    local ctx = ngx.ctx.ctx

    local midwares = route_service.find_prefix_midwares(ctx)
    local handler = function
    ()
        local matched,router = ctx.route.run(ctx)
        if matched then
            ctx:dispatch({
                proxy = router[1], params = router[2], midware = router[3], router = router[4]
            })
            return 200
        else
            return 404
        end
    end
    local  response = ctx.dispatcher:prepare_response(ctx.dispatcher:create_responser({
        handler, {}, midwares or {}
    })())
    if response.status ~= 200 then
        response:send()
    end
end

function ApiGateWay.rewrite(ApiGateWay)
    lw_utils.elapse_time_start("BALANCER_START")
    local ctx = ApiGateWay:init()
    plugins.load(ctx)
    route_service.load(ctx)
    load_cert_and_key(ctx)
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