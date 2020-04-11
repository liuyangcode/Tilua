

local class = require("pl.class")
local path = require "pl.path"
local path_exists = path.exists
local table_concat = table.concat
local stringx = require('pl.stringx')
local lstrip = stringx.lstrip
local split = stringx.split
local ctx = ngx.ctx
local var = ngx.var
local pl_utils = require('pl.utils')
local lw_utils = require('Tilua.util')
---@type request
local request = require('Tilua.request')
---@class app
class.app()

---初始化属性
function app:properties()
    self.multi_module = true
end
---_init
---@param app_instance app
function app:_init(app_instance)
    self:properties()

    module = app_instance.module or ''

    self.config = self.config or {}
    --共享全局app实例
    ctx.app_context = app_instance
end

---分发路由
---@return dispatch
function app:dispatch(...)
    if not self.dispatcher then
        self:init_dispatcher()
    end
    return self.dispatcher:run(...)
end

---获得路由分发器
function app:get_dispatcher()
    if not self.dispatcher then
        self:init_dispatcher()
    end
    return self.dispatcher
end

---初始化路由分发器
function app:init_dispatcher()
    local dispatcher = self:C('dispatch')
    assert(not lw_utils.empty(dispatcher), 'no dispatcher defined')
    local found, dispatch = pcall(require, dispatcher)
    if not found then
        error('not dispatcher defined')
    end
    assert(dispatch.run, 'dispatch must has a run method')
    self.dispatcher = dispatch(self)
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

---加载路由过滤器
---@return route
function app:get_route()
    if self.route then
        return self.route
    end
    local route = self:C('route_filter')
    local route_rules = self:C('route')
    if lw_utils.is_string(route) then
        local found, route_filter = pcall(require, route)
        if not found then
            assert(false, 'route filter named ' .. route .. ' not found')
        end
        assert(route_filter.run, 'route filter must has a run method')
        self.route = pl_utils.bind1(route_filter.run, route_filter(route_rules))
    elseif lw_utils.callable(route) then
        self.route = pl_utils.bind1(route, route_rules)
    elseif type(route) == 'table' then
        assert(route.run, 'route filter must has a run method')
        route.rules = route_rules
        self.route = pl_utils.bind1(route.run, route)
    end
    return self.route
end

---get_cache
---@param config table
---@return cache
function app:get_cache(config)
    if self.cache then
        return self.cache:instance(config)
    end
    self.cache = require "Tilua.cache"(self)
    return self.cache:instance(config)
end

---应用初始化
function app:init()
    self.pathinfo = var.uri
    if self.multi_module and lw_utils.empty(self.module) then
        self.module = table.unpack(split(lstrip(self.pathinfo, '/'), '/'))
    end
    --加载系统默认配置
    lw_utils.extend(self.config, require "Tilua.config")
    --加载应用路由定义
    pcall(require, self.app_name .. '.routes')
    if self.module and self.multi_module then
        --加载模块路由配置
        pcall(require, table_concat({
            self.app_name,
            self.module,
            'routes'
        }, '.'))

        self.module_path = self.app_path .. self.module
        if not path_exists(self.module_path) then
            error('module ' .. self:get_module() .. ' not found')
        end
        local found, module_config = pcall(require, table_concat({
            self.app_name,
            self.module,
            'config'
        }, '.'))
        if found then
            self:load_config(module_config)
        end
    end
end

---加载配置
---@param config table
function app:load_config(config)
    lw_utils.extend(self.config, config)
end

---获取当前模块名称
function app:get_module()
    return self.module
end

---获取配置
function app:get_config(...)
    return self:C(...)
end
function app:C(name, value)
    if name and value then
        self.config[name] = value
        return true
    end
    return self.config[name] or ''
end

---handle
---@param request request
function app:handle(request)
    (self:dispatch(self:get_route()(request)))(self):send()
end

function app:start()
    self:init()
    self:handle(request.capture())
end

function app.error_handle(err)
    ngx.say(string.gsub(err, "\n", "<br>") .. "<br>")
    ngx.say(string.gsub(debug.traceback(), "\n", "<br>"))
end

function app.default_dispatch_hanlder()
    return function()
        ngx.say('i\'m a default handler')
    end
end

function app:run()
    if (self.debug) then
        xpcall(function(app)
            app:start()
        end, app.error_handle, self)
    else
        self:start()
    end
    require("Tilua.db").close()
end

function app.derive()
    return class(app)
end

return app