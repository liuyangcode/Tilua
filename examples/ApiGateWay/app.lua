local ApiGateWay = require("Tilua.app").define()
local lw_utils = require("Tilua.utils.util")
local route_service = require("ApiGateWay.service.routes")
local balancer = require("ngx.balancer")
local plugins = require("ApiGateWay.service.plugins")
local do_chain_call = require("ApiGateWay.util").do_chain_call
local call_midwares_stack = require("ApiGateWay.util").call_midwares_stack
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
local monitor = require("ApiGateWay.midware.monitor")
local balancer_service = require("ApiGateWay.balancer")
ApiGateWay.name = "ApiGateWay"
ApiGateWay.debug = true
ApiGateWay.status = 'dev'


function ApiGateWay.on_init_by_lua(ctx)
    local ngx = ngx
    local context = {
        config = ctx.config
    }
    local localtime = ngx.localtime
    local logger = ApiGateWay.get_logger(context)
    require("ApiGateWay.balancer").init()
    logger:write("\n[", localtime(), "]", "ApiGateWay Worker init success worker pid ", ngx.worker.pid())
    logger:flush()
end


function ApiGateWay.on_init_worker()
    --local healthcheck = require("resty.healthcheck")
    --
    local we = require "resty.worker.events"
    local ok, err = we.configure({
        shm = "events", -- defined by "lua_shared_dict"
        timeout = 2, -- life time of unique event data in shm
        interval = 1, -- poll interval (seconds)

        wait_interval = 0.010, -- wait before retry fetching event data
        wait_max = 0.5, -- max wait time before discarding event
        shm_retries = 999, -- retries for shm fragmentation (no memory)
    })
    if not ok then
        ngx.log(ngx.ERR, "failed to configure worker events: ", err)
        return
    end
    we.register(balancer_service.ev_handler)
    monitor.init_worker(ApiGateWay)
end

function ApiGateWay.ssl_certificate()
    local sn, err = server_name()
    if err then
        ngx.log(ERR, "could not get server name ", err)
        return ngx.exit(ngx.ERROR)
    end

    ngx.log(ngx.ERR, "ApiGateWay.ssl_certificate server name ",sn)
    local cert_and_key, err = ssl_certificate.find_key_and_cert(sn)
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


---on_app_init
---context:app
function ApiGateWay:on_app_init()
    self.logger:debug("on_app_init --- ", self.name)
end

---context:app
function ApiGateWay:on_rewrite()
    self:set_phase('rewrite')
    call_midwares_stack(self)

    lw_utils.elapse_time_start("BALANCER_START")
    plugins.load(self)
    route_service.load(self)
    load_cert_and_key(self)
end

function ApiGateWay:set_phase(phase)
    self._phase = phase
end

function ApiGateWay:get_phase()
    return self._phase
end
---access phase
---context:app
function ApiGateWay:on_access()
    self:set_phase('access')

    local midwares = route_service.find_prefix_midwares(self)
    local response = do_chain_call(
            self,
            midwares or {},
            function()
                return self.dispatcher:run(self.route.run(self))
            end
    )
    local tresponse = type(response)
    ---response has body to send
    ---then send response
    if tresponse ~= 'table' then
        ngx.exit(response)
    elseif tresponse =='table' and response.body then
        response:send()
    else
        ngx.ctx.peer = response
    end
end

---header_filter phase
---context:app
function ApiGateWay:on_header_filter()
    self:set_phase('header_filter')

    call_midwares_stack(self)

    local access = ngx.ctx.access or {}
    access.content_type = ngx.header.content_type
    access.content_length = ngx.header.content_length
    access.response_code = ngx.status

    ngx.header['X-Powered-By'] = 'TGateWay by Tilua'
    ngx.header['Server'] = nil

    ngx.ctx.access = access
end

---body_filter phase
---context:app
function ApiGateWay:on_body_filter()
    self:set_phase('body_filter')
    call_midwares_stack(self)

    self.logger:debug("on_body_filter ", self.name)
end
---log_by_lua phase
---context:app
function ApiGateWay:on_app_end()
    self:set_phase('log')
    call_midwares_stack(self)

    ngx.log(ngx.ERR,'----',self.request.server_port,self.phase)
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

return ApiGateWay