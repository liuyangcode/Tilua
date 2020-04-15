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
local midware_manager = require('Tilua.midware_manager')
---@type request
local request = require('Tilua.request')
---@class app
---properties
local app = class()
local _cache = nil
local _dispatcher = nil
local _route = nil
local _config = {}
local _context = nil
---_init
---@param app_instance app
function app:_init(app_instance)
    --共享全局app实例
    ctx.app_context = app_instance
    _context = self
    self:catch(self.magic)
end
---分发路由
---@return dispatch
function app:dispatch(...)
    if not _dispatcher then
        self:init_dispatcher()
    end
    return _dispatcher:run(...)
end
---魔术方法
---@param name string
function app:magic(name)
    if rawget(self, 'get_' .. name) then
        return self['get_' .. name](_context)
    end
end
---获得路由分发器
function app:get_dispatcher()
    if not _dispatcher then
        self:init_dispatcher()
    end
    return _dispatcher
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
    _dispatcher = dispatch(self)
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
    if _route then
        return _route
    end
    local route = self:C('route_filter')
    local route_rules = self:C('route')
    if lw_utils.is_string(route) then
        local found, route_filter = pcall(require, route)
        if not found then
            assert(false, 'route filter named ' .. route .. ' not found')
        end
        assert(route_filter.run, 'route filter must has a run method')
        _route = pl_utils.bind1(route_filter.run, route_filter(route_rules))
    elseif lw_utils.callable(route) then
        _route = pl_utils.bind1(route, route_rules)
    elseif type(route) == 'table' then
        assert(route.run, 'route filter must has a run method')
        route.rules = route_rules
        _route = pl_utils.bind1(route.run, route)
    end
    return _route
end
function app:get_model()
    return require("Tilua.model").init_context(self)
end

function app:get_db()
    return require("Tilua.db").init_context(self)

end
---初始化缓存
function app:init_cache()
    if not _cache then
        _cache = require "Tilua.cache"
        _cache.init(self)
    end
    return _cache
end

function app:get_cache()
    if not _cache then
        self:init_cache()
    end
    return _cache
end
function app:get_logger()
    return require("Tilua.log")
end
---应用初始化
function app:init()
    --加载系统默认配置
    lw_utils.extend(_config, require "Tilua.config.default")
    local _, config = pcall(require, table_concat({
        self.app_name,
        "config",
        self.status
    }, '.'))

    self:load_config(config or {})
    self:init_cache()
    midware_manager.init_group(self:C('midware_group'))
    --加载应用路由定义
    pcall(require, self.app_name .. '.routes')
end

---加载配置
---@param config table
function app:load_config(config)
    lw_utils.extend(_config, config)
end

---获取配置
function app:get_config(...)
    return self:C(...)
end

function app:C(name, value)
    if name and value then
        _config[name] = value
        return true
    end
    local config = _config
    if not name then
        return _config
    end
    local properties = split(name, '.')
    for i = 1, #properties do
        config = config[properties[i]]
    end
    return config
end

---handle
---@param request request
function app:handle(request)
    (self:dispatch(self.route(request)))():send()
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
end

function app.derive()
    return class(app)
end

return app