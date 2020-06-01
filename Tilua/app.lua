local class = require("pl.class")
local path = require "pl.path"
local table_concat = table.concat
local stringx = require('pl.stringx')
local split = stringx.split
local lw_utils = require('Tilua.util')
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
function app:get_cache()
    self.cache = cache_manager.new(self)
    return self.cache
end
function app:get_db()
    self.db = db_manager.new(self)
    return self.db
end
function app:get_model()
    self.model = model_manager.new(self)
    return self.model
end

function app:get_logger()
    self.logger = logger_class.new(self.config.log)
    return self.logger
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
function app.request_end(inst)
    local ctx = ngx.ctx.ctx
    ctx.logger:flush()
end
function app.body_filter()
end
function app.header_filter()
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
        app_instance.on_startup()
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
    ctx:dispatch(ctx.route.run(ctx))()
    ctx.db:close()
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