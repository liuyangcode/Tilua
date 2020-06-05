local class = require("pl.class")
local path = require "pl.path"
local table_concat = table.concat
local stringx = require('pl.stringx')
local split = stringx.split
local lw_utils = require('Tilua.util')
local bind1 = require("pl.utils").bind1
local deepcopy = require('pl.tablex').deepcopy
local model_manager = require("Tilua.model.manager")
local db_manager = require("Tilua.db.manager")
local midware_manager = require("Tilua.model.manager")
local cache_manager = require("Tilua.cache.manager")

---@class app
local app = class()
local logger_class = nil

local request = nil
---全局配置文件
local configs = {}
---_init
function app:_init()
    --共享全局app实例
    self:catch(function(_, name)
        return self:magic(name)
    end)
end
---分发路由
---@return dispatch
function app:dispatch(...)
    local dispatcher = self.config.dispatch
    self.logger:debug('init dispatch named:', dispatcher)
    assert(not lw_utils.empty(dispatcher), 'no dispatcher defined')
    local found, dispatch = pcall(require, dispatcher)
    if not found then
        error('not dispatcher defined')
    end
    assert(dispatch.run, 'dispatch must has a run method')
    self.dispatcher = dispatch(self)
    return self.dispatcher:run(...)
end
---魔术方法
---@param name string
function app:magic(name)
    if rawget(self, 'get_' .. name) then
        return self['get_' .. name](self)
    elseif app['get_' .. name] then
        return app['get_' .. name](self)
    elseif rawget(app, name) then
        return app[name]
    end
end
function app:get_midware()
    self.midware = midware_manager.new(self)
    return self.midware
end
function app:get_response()
    self.response = require("Tilua.response").new(self)
    return self.response
end
---get_html_cache_interceptor
---@return page
function app:get_html_cache_interceptor()
    if self.cache_interceptor then
        return self.cache_interceptor
    end
    self.cache_interceptor = require "Tilua.cache.page"(self)
    return self.cache_interceptor
end

---@return cache
function app.get_cache(ctx)
    ctx.cache = cache_manager.new(ctx.config, ctx.logger)
    if ctx.on_app_handled then
        ctx:on_app_handled(bind1(ctx.cache.close, ctx.cache))
    end
    return ctx.cache
end

function app.get_db(ctx)
    ctx.db = db_manager.new({
        ctx = ctx.config,
        logger = ctx.logger
    })
    if ctx.on_app_handled then
        ctx:on_app_handled(bind1(ctx.db.close, ctx.db))
    end
    return ctx.db
end

function app.get_model(ctx)
    ctx.model = model_manager.new(ctx)
    return ctx.model
end

function app.get_logger(ctx)
    ctx.logger = logger_class.new(ctx.config.log)
    if ctx.on_request_end then
        ctx:on_request_end(bind1(ctx.logger.flush, ctx.logger))
    end
    return ctx.logger
end

function app:get_view()
    self.view = require("Tilua.view")(self)
    return self.view
end

local function init_application(app_instance)
    local ngx = ngx
    ngx.update_time()

    local ctx = ngx.ctx
    local context = app_instance()
    ctx.ctx = context
    if context.on_app_init then
        context.on_app_init(context)
    end
end

function app:get_request()
    self.request = request.capture(self)
    return self.request
end
---应用初始化
function app.init(app_instance)
    if app_instance.debug then
        xpcall(init_application, app.error_handle, app_instance)
    else
        init_application(app_instance)
    end
end

function app:get_config()
    return configs[self.name]
end

function app:on_request_end(callback)
    if not self.request_end_callbacks then
        self.request_end_callbacks = {}
    end
    table.insert(self.request_end_callbacks, callback)
    return self
end

function app.request_end(inst)
    local ctx = ngx.ctx.ctx
    if ctx.on_app_end then
        ctx:on_app_end(ctx)
    end
    if ctx then
        lw_utils.foreach(ctx.request_end_callbacks, function(callback)
            callback()
        end)
    end
end
--output filters may be called multiple times for a single request
function app.body_filter()
    local ngx = ngx
    local ctx = ngx.ctx.ctx
    if ctx.on_body_filter then
        ctx:on_body_filter(ngx.arg[1])
    end
    ctx.logger:debug(ctx.name," App body filter phase ")
end

function app.header_filter()
    local ctx = ngx.ctx.ctx
    if ctx.on_header_filter then
        ctx:on_header_filter()
    end
    ctx.logger:debug(ctx.name," App header filter phase ")
end

function app:on_app_handled(func)
    if not self.after_app_handled_callbacks then
        self.after_app_handled_callbacks = {}
    end
    table.insert(self.after_app_handled_callbacks, func)
    return self
end

function app.init_worker(app_instance)
    --init_worker
end
---worker初始化
---@param app_instance app
function app.startup(app_instance)
    local app_config = {}
    local appname = app_instance.name
    --加载系统默认配置
    lw_utils.extend(app_config, deepcopy(require "Tilua.config.default"))
    local _, config = pcall(require, table_concat({
        appname,
        "config",
        app_instance.status
    }, '.'))
    if config then
        lw_utils.extend(app_config, config or {})
    end
    midware_manager = require('Tilua.midware.manager').load(app_config)
    request = require('Tilua.request')
    app.route = require('Tilua.route')
    app.route.set_app_name(appname)
    app_config.log.path = path.join(app_instance.path, app_config.log.path)
    logger_class = require("Tilua.log").init(app_config.log)
    --加载应用自定义路由
    pcall(require, appname .. '.routes')
    --解析路由
    app.route.init_rule_caches(app_config.route)
    configs[appname] = app_config
    if app_instance.on_startup then
        app_instance.on_startup(app_config)
    end
end

function app:C(name)
    local config = deepcopy(configs[self.name])
    if not name then
        return config
    end
    local properties = split(name, '.')
    for i = 1, #properties do
        config = config[properties[i]]
    end
    return config
end

---unpack
---@return request,response,cache,table
function app:unpack()
    return self.request, self.response, self.cache, self.config
end

function app.error_handle(err)
    ngx.print({
        string.gsub(err or "", "\n", "<br>") .. "<br>",
        string.gsub(debug.traceback(), "\n", "<br>")
    })
end

function app.run()
    local ctx = ngx.ctx.ctx
    assert(ctx, 'no application context found')
    ctx:dispatch(ctx.route.run(ctx))()
    lw_utils.foreach(ctx.after_app_handled_callbacks, function(callback)
        callback()
    end)
    if (ctx.debug) then
        xpcall(function(app)
            app.response:send()
        end, app.error_handle, ctx)
    else
        ctx.response:send()
    end
end

function app.derive()
    return class(app)
end

return app