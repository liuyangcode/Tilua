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
local midware_manager = require("Tilua.midware.manager")
local cache_manager = require("Tilua.cache.manager")
local template = require "resty.template"
---@class app
local app = class()
local logger_class = nil

local request = nil
---全局配置文件
local configs = {}
---_init
function app:_init()
    self:initialize()
end
function app:initialize()
    self.config = configs[self.name]
    self:init_logger()
    self.request = request.capture(self)
    self.response = require("Tilua.response").new(self)
    self:init_view()
    self.midware = midware_manager.new(self)
    self:init_cache_manager()
    self:init_db_manager()
    self:init_model_manager()
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
function app:init_cache_manager()
    self.cache = cache_manager.new(self.config, self.logger)
    if self.on_app_handled then
        self:on_app_handled(bind1(self.cache.close, self.cache))
    end
    return self.cache
end

function app:init_db_manager()
    self.db = db_manager.new({
        ctx = self.config,
        logger = self.logger
    })
    if self.on_app_handled then
        self:on_app_handled(bind1(self.db.close, self.db))
    end
    return self.db
end

function app:init_model_manager()
    self.model = model_manager.new(self)
    return self.model
end

function app.init_logger(ctx)
    ctx.logger = logger_class.new(ctx.config.log)
    if ctx.on_request_end then
        ctx:on_request_end(bind1(ctx.logger.flush, ctx.logger))
    end
    return ctx.logger
end

function app:init_view()
    self.view = require("Tilua.view")(self)
    return self.view
end

local function init_application(app_instance)
    local ngx = ngx
    ngx.update_time()

    local ctx = ngx.ctx
    lw_utils.elapse_time_start('app_excution_time')
    local context = app_instance()
    ctx.ctx = context
    if context.on_app_init then
        context.on_app_init(context)
    end
    return context
end

---应用初始化
function app.init(app_instance)
    local context = {}
    if app_instance.debug then
        xpcall(function()
            context = init_application(app_instance)
        end, app.error_handle)
    else
        context = init_application(app_instance)
    end
    return context
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
    if not ctx then
        return
    end
    if ctx.on_app_end then
        ctx:on_app_end(ctx)
    end
    ctx.logger:debug('App Request elapsed time ', lw_utils.elapse_time_end('app_excution_time') or 0, ' ms')
    if ctx then
        lw_utils.foreach(ctx.request_end_callbacks or {}, function(callback)
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
    ctx.logger:debug(ctx.name, " App body filter phase ")
end

function app.header_filter()
    local ctx = ngx.ctx.ctx
    if ctx.on_header_filter then
        ctx:on_header_filter()
    end
    ctx.logger:debug(ctx.name, " App header filter phase ")
end

function app:on_app_handled(func)
    if not self.after_app_handled_callbacks then
        self.after_app_handled_callbacks = {}
    end
    table.insert(self.after_app_handled_callbacks, func)
    return self
end

function app.init_worker(app_instance)
    ----init_worker
    --if app_instance.init_worker then
    --    app_instance:init_worker()
    --end
end

local function init_view_engine(root)
    local view_path = path.join(root, 'view', '')
    local view_cache_path = path.join(root, 'cache', 'view', '')
    local html_cache_path = path.join(root, 'cache', 'html', '')

    local makepath = require "pl.dir".makepath
    local path_exists = path.exists
    if not path_exists(view_cache_path) then
        local _, err = makepath(view_cache_path)
        assert(not err, 'dir ' .. view_cache_path .. ' write ' .. err)
    end
    if not path_exists(html_cache_path) then
        local _, err = makepath(html_cache_path)
        assert(not err, 'dir ' .. html_cache_path .. ' write ' .. (err or ''))
    end
    local view_engine = template.new({
        root = root
    })
    return {
        template = view_engine,
        view = view_path,
        root = root,
        cache_key_prefix = view_path,
        view_cache_path = path.join('cache', 'view', ''),
        view_cache_abs_path = view_cache_path,
        html_cache_path = html_cache_path
    }
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

    app_instance.view_engine = init_view_engine(app_instance.path)
    app_instance.view_engine.template.caching(not app_instance.debug)
    app_instance.route = require('Tilua.route')
    app_instance.route.set_app_name(appname)
    app_config.log.path = path.join(app_instance.path, app_config.log.path)
    logger_class = require("Tilua.log").init(app_config.log)
    --加载应用自定义路由
    pcall(require, appname .. '.routes')
    --解析路由
    app_instance.route.init_rule_caches(app_config.route)
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
    return lw_utils.index_value(config, name)
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

    if (ctx.debug) then
        xpcall(function()
            ctx:dispatch(ctx.route.run(ctx))
            lw_utils.foreach(ctx.after_app_handled_callbacks or {}, function(callback)
                callback()
            end)
            ctx.response:send()
        end, app.error_handle)
    else
        ctx:dispatch(ctx.route.run(ctx))
        lw_utils.foreach(ctx.after_app_handled_callbacks or {}, function(callback)
            callback()
        end)
        ctx.response:send()
    end
end

function app.derive()
    return class(app)
end

return app