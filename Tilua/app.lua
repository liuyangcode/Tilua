local class = require("pl.class")
local path = require "pl.path"
local table_concat = table.concat
local stringx = require('pl.stringx')
local split = stringx.split
local lw_utils = require('Tilua.util')
---@class app
---properties
local app = class()
local logger_class = nil
local model_class = nil
local midware_manager = nil
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
    self.logger:debug('app:get_response')
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

function app:get_cache()
    local caches = {
        caches = {}
    }
    self.cache = setmetatable(caches, {
        __index = function(m, name)
            if type(name) == 'string' then
                name = { type = name }
            end
            local hash = lw_utils.get_hash(name)
            if caches.caches[hash] then
                return caches.caches[hash]
            end
            local ok, driver = pcall(require, "Tilua.cache.driver." .. name.type)
            assert(ok, 'unsupported cache type ' .. name.type)
            caches.caches[hash] = driver(name, self)
            return caches.caches[hash]
        end
    })
    return self.cache
end

function app:get_model()
    local models = {
        models = {}
    }
    self.model = setmetatable(models, {
        __index = function(m, name)
            self.logger:debug("start Init Model named ", name)
            local mod = lw_utils.import(table.concat({
                self.name,
                'model',
                name
            }, '.'))
            if mod then
                models.models[name] = mod()
                return models.models[name]
            end
            if models.models[name] then
                self.logger:debug("Model named ", name, " has already inited ")
                return models.models[name]
            end
            models.models[name] = model_class(name)
            return models.models[name]
        end
    })
    return self.model
end

function app:get_logger()
    self.logger = logger_class.new(self)
    return self.logger
end

function app:get_db()
    self.db = require("Tilua.db").new(self)
    return self.db
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
    context.request.capture()
    context:dispatch(context.route.run(context))()
end
---应用初始化
function app.init(app_instance)
    if app_instance.debug then
        xpcall(init_application, app.error_handle, app_instance)
    else
        init_application(app_instance)
    end
end

function app.request_end()
    local ctx = ngx.ctx.ctx
    ctx.db:close()
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
    local _config = {}
    --加载系统默认配置
    lw_utils.extend(_config, require "Tilua.config.default")
    local _, config = pcall(require, table_concat({
        app_instance.name,
        "config",
        app_instance.status
    }, '.'))
    if config then
        lw_utils.extend(_config, config or {})
    end
    app.config = _config
    app.cache = require "Tilua.cache" .init(app_instance)
    midware_manager = require('Tilua.midware.manager').load(_config)
    app.request = require('Tilua.request')
    app.route = require('Tilua.route')
    model_class = require('Tilua.model')
    _config.log.path = path.join(app_instance.path, _config.log.path)
    logger_class = require("Tilua.log").init(_config.log)
    pcall(require, app_instance.name .. '.routes')
    app.route.init_rule_caches(_config.route)
end

function app:C(name)
    local config = app.config
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