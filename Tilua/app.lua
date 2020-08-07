local lw_utils = require('Tilua.utils.util')
local path = require("Tilua.utils.path")
local path_exists = path.isdir
local path_join = path.join
local import = lw_utils.import
local bind1 = require("Tilua.utils.util").bind1
local deepcopy = require('Tilua.utils.tables').deep_copy
local makepath = require "pl.dir".makepath

local model_manager = require("Tilua.model")
local db_manager = require("Tilua.db")
local midware_manager = require("Tilua.midware")
local cache_manager = require("Tilua.cache")
local template = require "resty.template"
local class = require("Tilua.utils.class")
---@class app
local app = class.define()
local logger_class = nil

local request = nil
---全局配置文件
local configs = {}
---_construct
function app:_construct()
    self.midware = midware_manager(self)
end
----------------------- lazy init begin -------------------------
---
---context: app
---
---lazy init dispatcher
---@return dispatch
function app:get_dispatcher()
    local dispatcher = self.config.dispatch
    self.logger:debug('init dispatch named:', dispatcher)
    assert(not lw_utils.empty(dispatcher), 'no dispatcher defined')
    local dispatch = import(dispatcher)
    if not dispatch then
        error('not dispatcher defined')
    end
    assert(dispatch.run, 'dispatch must has a run method')
    self.dispatcher = dispatch(self)
    return self.dispatcher
end

---
---context: app
---
---lazy init request
---@return request
function app:get_request()
    self.request = request.capture(self)
    return self.request
end

---
---context: app
---
---lazy init response
---@return response
function app:get_response()
    self.response = import("Tilua.response")(self)
    return self.response
end

---
---context: app
---
---lazy init cache manager
---@return cache_manager
function app:get_cache()
    self.cache = cache_manager(self.config, self.logger)
    self:on_app_handled(bind1(self.cache.close, self.cache))
    return self.cache
end

---
---context: app
---
---lazy init db manager
---@return db_manager
function app:get_db()
    self.db = db_manager({
        ctx = self.config,
        logger = self.logger
    })
    self:on_app_handled(bind1(self.db.close, self.db))
    return self.db
end
---
---context: app
---
---lazy init model manager
---@return model_manager
function app:get_model()
    self.model = model_manager(self)
    return self.model
end

---
---context: app
---
---lazy init logger
---@return log
function app:get_logger()
    self.logger = logger_class.new(self.config.log)
    return self.logger
end

---
---context: app
---
---lazy init view
---@return view
function app:get_view()
    self.view = import("Tilua.view")(self)
    return self.view
end

---
---context:app
---
---lazy init config
---
---@return table
function app:get_config(key)
    if key then
        return lw_utils.index_value(self.config, key)
    end
    self.config = deepcopy(configs[self.name])
    return self.config
end

---unpack
---@return request,response,cache,table
function app:unpack()
    return self.request, self.response, self.cache, self.config
end

----------------------- lazy init end -------------------------

--------------- lua nginx module directives begin -------------------

----------- initialization phase --------------

local function init_view_engine(root)
    local view_path = path_join(root, 'view', '')
    local cache_path = path_join(root, 'cache', '')
    local view_cache_path = path_join(root, 'cache', 'view', '')
    local html_cache_path = path_join(root, 'cache', 'html', '')

    lw_utils.foreach({ cache_path, view_cache_path, html_cache_path }, function(p)
        if not path_exists(p) then
            local _, err = makepath(p)
            if err then
                error('dir ' .. p .. ' write ' .. err)
            end
        end
    end)
    local view_engine = template.new({
        root = root
    })
    return {
        template = view_engine,
        view = view_path,
        root = root,
        cache_key_prefix = view_path,
        view_cache_path = path_join('cache', 'view', ''),
        view_cache_abs_path = view_cache_path,
        html_cache_path = html_cache_path
    }
end

---init_by_lua_block
---context: http
---
---frequency:once, master worker process start
---
---phase: loading-config
---
---Runs the Lua code when the Nginx master process (if any) is loading the Nginx config file.
---
---When Nginx receives the HUP signal and starts reloading the config file,
---the Lua VM will also be re-created and init_by_lua will run again on the new Lua VM.
---In case that the lua_code_cache directive is turned off (default on), the init_by_lua handler will run upon every request
---because in this special mode a standalone Lua VM is always created for each request.
---
---Usually you can pre-load Lua modules at server start-up by means of this hook and take advantage of modern operating systems' copy-on-write (COW) optimization.
---doc from https://github.com/openresty/lua-nginx-module#init_by_lua
---
---@param app_instance app
---@return any
---
function app.init_by_lua(app_instance)
    ---if not class.is_sub_class(app,app_instance) then
    ---    error("instance must be derived from Tilua.app"..app.identifier..app_instance.identifier)
    ---end
    if app_instance._inited_by_lua then
        return
    end
    local app_config = {}
    local appname = app_instance.name
    app_instance.path = path.get_module_path(appname, 'app')
    ---加载系统默认配置
    lw_utils.extend(app_config, deepcopy(import "Tilua.config.default"))
    lw_utils.foreach({ 'default', app_instance.status }, function(status)
        local config = lw_utils.import(appname, "config", status)
        if type(config) == 'table' then
            lw_utils.extend(app_config, config or {})
        end
    end)

    midware_manager = import('Tilua.midware').load(app_config)
    request = import('Tilua.request')
    app_instance.view_engine = init_view_engine(app_instance.path)
    app_instance.view_engine.template.caching(not app_instance.debug)
    app_instance.route = import('Tilua.route')
    app_instance.route.set_app_name(appname)
    app_config.log.path = path_join(app_instance.path, app_config.log.path)
    logger_class = import("Tilua.log").init(app_config.log)
    ---加载应用自定义路由
    local route = lw_utils.import(appname .. '.routes')
    if type(route) == 'function' then
        route(app_instance, app_instance.route)
    end
    ---解析路由
    app_instance.route.init_rule_caches(app_config.route)

    configs[appname] = app_config

    if app_instance.on_init_by_lua then
        app_instance.on_init_by_lua(app_config)
    end

    app_instance._inited_by_lua = true
end

---init_worker_by_lua_block
---context: http
---
---frequency:every worker process start
---
---phase: starting-worker
---
---Runs the specified Lua code upon every Nginx worker process's startup when the master process is enabled.
---
---When the master process is disabled, this hook will just run after init_by_lua*.
---
---This hook is often used to create per-worker reoccurring timers (via the ngx.timer.at Lua API), either for backend health-check or other timed routine work.
---
---doc from https://github.com/openresty/lua-nginx-module#init_worker_by_lua_block
---
function app.init_worker_by_lua(app_instance)
    if app_instance.on_init_worker then
        app_instance.on_init_worker()
    end
end

----------- rewrite/access phase --------------
---
---ssl_certificate_by_lua_block
---
---context: server
---
---frequency:every request
---
---phase: right-before-SSL-handshake
---
---This directive runs user Lua code when Nginx is about to start the SSL handshake for the downstream SSL (https) connections.
---
---It is particularly useful for setting the SSL certificate chain and the corresponding private key on a per-request basis.
---
---It is also useful to load such handshake configurations nonblockingly from the remote (for example, with the cosocket API).
---
---And one can also do per-request OCSP stapling handling in pure Lua here as well.
---
---Another typical use case is to do SSL handshake traffic control nonblockingly in this context, with the help of the lua-resty-limit-traffic#readme library, for example.
---
---One can also do interesting things with the SSL handshake requests from the client side, like rejecting old SSL clients using the SSLv3 protocol or even below selectively.
---
---The ngx.ssl and ngx.ocsp Lua modules provided by the lua-resty-core library are particularly useful in this context.
---
---You can use the Lua API offered by these two Lua modules to manipulate the SSL certificate chain and private key for the current SSL connection being initiated.
---
---This Lua handler does not run at all, however, when Nginx/OpenSSL successfully resumes the SSL session via SSL session IDs or TLS session tickets for the current SSL connection.
---
---In other words, this Lua handler only runs when Nginx has to initiate a full SSL handshake.
---
---doc from https://github.com/openresty/lua-nginx-module#ssl_certificate_by_lua_block
---
function app.ssl_certificate()

end


-----应用初始化
--function app.init(app_instance)
--    local context = {}
--    if app_instance.debug then
--        xpcall(function()
--            context = init_application(app_instance)
--        end, app.error_handle)
--    else
--        context = init_application(app_instance)
--    end
--    return context
--end
--
--local function init_application(app_instance)
--
--end
---set_by_lua
---context: server, server if, location, location if
---
---phase: rewrite
---
---Executes code with optional input arguments $arg1 $arg2 ..., and returns string output to $res.
---
---The code in <lua-script-str> can make API calls and can retrieve input arguments from the ngx.arg table (index starts from 1 and increases sequentially).
---
---This directive is designed to execute short, fast running code blocks as the Nginx event loop is blocked during code execution. Time consuming code sequences should therefore be avoided.
---
---This directive is implemented by injecting custom commands into the standard ngx_http_rewrite_module's command list.
---
---Because ngx_http_rewrite_module does not support nonblocking I/O in its commands, Lua APIs requiring yielding the current Lua "light thread" cannot work in this directive.
---
---At least the following API functions are currently disabled within the context of set_by_lua:
---
---Output API functions (e.g., ngx.say and ngx.send_headers)
---Control API functions (e.g., ngx.exit)
---Subrequest API functions (e.g., ngx.location.capture and ngx.location.capture_multi)
---Cosocket API functions (e.g., ngx.socket.tcp and ngx.req.socket).
---Sleeping API function ngx.sleep.
---In addition, note that this directive can only write out a value to a single Nginx variable at a time.
---
---However, a workaround is possible using the ngx.var.VARIABLE interface.
---
function app.set_by_lua(app_instance)
    local ngx = ngx
    ngx.update_time()
    local ctx = ngx.ctx.ctx
    if ctx then
        return
    end
    if not app_instance._inited_by_lua then
        app.init_by_lua(app_instance)
    end
    lw_utils.elapse_time_start('app_excution_time')
    local context = app_instance()
    if context.on_app_init then
        context:on_app_init()
    end
    ngx.ctx.ctx = context
    return context
end
---
---rewrite_by_lua
---
---context: http, server, location, location if
---
---frequency: every request
---phase: rewrite tail
---
---Acts as a rewrite phase handler and executes Lua code  for every request.
---
---The Lua code may make API calls and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).
---
---doc from https://github.com/openresty/lua-nginx-module#rewrite_by_lua_block
---
function app.rewrite_by_lua(app_instance)
    if app_instance.on_rewrite then
        app_instance:on_rewrite()
    end
end

---
---access_by_lua
---
---context: http, server, location, location if
---
---frequency:every request
---
---phase: access tail
---
---Acts as an access phase handler and executes Lua code for every request.
---
---The Lua code may make API calls and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).
---doc from https://github.com/openresty/lua-nginx-module#access_by_lua
---
function app.access_by_lua(app_instance)
    if app_instance.on_access then
        app_instance:on_access()
    end
end
-------------- content phase -----------------

---
---content_by_lua
---
---context: location, location if
---
---frequency:every request
---
---phase: content
---
---Acts as a "content handler" and executes Lua code  for every request.
---
---The Lua code may make API calls and is executed as a new spawned coroutine in an independent global environment (i.e. a sandbox).
---
---doc from https://github.com/openresty/lua-nginx-module#content_by_lua
---
function app.content_by_lua(app_instance)
    local ctx = ngx.ctx.ctx
    if not ctx then
        ctx = app_instance:set_by_lua()
        if not ctx then
            error('no application context found')
        end
    end
    xpcall(function()
        ctx:dispatch(ctx.route.run(ctx))
        lw_utils.foreach(ctx.after_app_handled_callbacks or {}, function(callback)
            callback()
        end)
        ctx.response:send()
    end, app.error_handle)
end

---
---header_filter_by_lua
---
---context: http, server, location, location if
---
---frequency:every request
---
---phase: output-header-filter
---
---Note that the following API functions are currently disabled within this context:
---
---Output API functions (e.g., ngx.say and ngx.send_headers)
---Control API functions (e.g., ngx.redirect and ngx.exec)
---Subrequest API functions (e.g., ngx.location.capture and ngx.location.capture_multi)
---Cosocket API functions (e.g., ngx.socket.tcp and ngx.req.socket).
---
---doc from https://github.com/openresty/lua-nginx-module#header_filter_by_lua
---
function app.header_filter_by_lua(app_instance)
    if app_instance.on_header_filter then
        app_instance.on_header_filter()
    end
end
---body_filter_by_lua
---
---context: http, server, location, location if
---
---phase: output-body-filter
---
---frequency:every request
---
---The input data chunk is passed via ngx.arg[1] (as a Lua string value) and the "eof" flag indicating the end of the response body data stream is passed via ngx.arg[2] (as a Lua boolean value).
---
---Behind the scene, the "eof" flag is just the last_buf (for main requests) or last_in_chain (for subrequests) flag of the Nginx chain link buffers.
---(Before the v0.7.14 release, the "eof" flag does not work at all in subrequests.)
---Note that the following API functions are currently disabled within this context due to the limitations in Nginx output filter's current implementation:
---
---Output API functions (e.g., ngx.say and ngx.send_headers)
---
---Control API functions (e.g., ngx.exit and ngx.exec)
---
---Subrequest API functions (e.g., ngx.location.capture and ngx.location.capture_multi)
---
---Cosocket API functions (e.g., ngx.socket.tcp and ngx.req.socket).
---
---Nginx output filters may be called multiple times for a single request because response body may be delivered in chunks.
---
---Thus, the Lua code specified by in this directive may also run multiple times in the lifetime of a single HTTP request.
---
---doc from https://github.com/openresty/lua-nginx-module#body_filter_by_lua
---
function app.body_filter_by_lua(app_instance)
    if app_instance.on_body_filter then
        app_instance.on_body_filter()
    end
end

-------------- log phase -----------------

---
---log_by_lua
---
---context: http, server, location, location if
---
---phase: log
---
---Runs the Lua source code inlined as the <lua-script-str> at the log request processing phase.
---
---This does not replace the current access logs, but runs before.
---
---Note that the following API functions are currently disabled within this context:
---
---Output API functions (e.g., ngx.say and ngx.send_headers)
---Control API functions (e.g., ngx.exit)
---Subrequest API functions (e.g., ngx.location.capture and ngx.location.capture_multi)
---Cosocket API functions (e.g., ngx.socket.tcp and ngx.req.socket).
---
---doc from https://github.com/openresty/lua-nginx-module#log_by_lua
function app.log_by_lua(app_instance)
    local ctx = ngx.ctx.ctx
    if not ctx then
        return
    end

    if app_instance.on_app_end then
        app_instance.on_app_end()
    end

    ctx.logger:debug('App Request elapsed time ', lw_utils.elapse_time_end('app_excution_time') or 0, ' ms')
    ctx.logger:flush()
end
--------------- lua nginx module directives end -------------------

---分发路由
---@return dispatch
function app:dispatch(...)
    return self.dispatcher:run(...)
end

function app:on_app_handled(func)
    if not self.after_app_handled_callbacks then
        self.after_app_handled_callbacks = {}
    end
    table.insert(self.after_app_handled_callbacks, func)
    return self
end

function app.error_handle(err)
    ngx.print({
        string.gsub(err or "", "\n", "<br>") .. "<br>",
        string.gsub(debug.traceback(), "\n", "<br>")
    })
end

return app