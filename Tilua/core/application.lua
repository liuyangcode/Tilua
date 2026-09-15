local class = require("Tilua.utils.class")
local Container = require("Tilua.core.container")
local Context = require("Tilua.core.context")
local Exception = require("Tilua.core.exception")

local Application = class.define()

function Application:_construct(config)
    self.config = config or {}
    self.container = Container()
    self.router, self.middleware, self.invoker = nil, nil, nil
    self.booted, self.worker_initialized = false, false
    self.name = self.config.name or "application"
    self.env = self.config.env or self.config.status or "production"
end

function Application:boot()
    if self.booted then return self end
    self:register_core(); self:register_services(); self:load_router(); self:load_middleware(); self:load_controller()
    self.booted = true
    if type(self.config.boot) == "function" then self.config.boot(self) end
    return self
end

function Application:register_core()
    self.container:value("app", self); self.container:value("config", self.config); return self
end

function Application:register_services()
    if self.config.logger or self.config.log then
        self.container:singleton("logger", function()
            local Logger = require("Tilua.logging.logger")
            return Logger(self.config.log or self.config.logger)
        end)
    end
    if self.config.db then
        self.container:singleton("db", function()
            local M = require("Tilua.database.manager")
            local logger = self.container:has("logger") and self.container:get("logger") or nil
            return M(self.config.db, self.container, logger)
        end)
    end
    return self
end

function Application:load_router()
    if self.config.router then self.router = self.config.router
    elseif self.config.router_class then self.router = self.config.router_class(self.config.route or {})
    else self.router = require("Tilua.router.router")(self.config.route or {}) end
    if self.router.compile then self.router:compile() end
    self.container:value("router", self.router); return self
end
function Application:load_middleware()
    if self.config.middleware then self.middleware=self.config.middleware
    elseif self.config.middleware_class then self.middleware=self.config.middleware_class(self.config.middleware_config or {}) end
    if self.middleware then self.container:value("middleware",self.middleware) end; return self
end
function Application:load_controller()
    local Invoker=require("Tilua.controller.invoker")
    self.invoker=Invoker.new(self); self.container:value("invoker",self.invoker); return self
end
function Application:init_worker()
    if not self.booted then self:boot() end
    if self.worker_initialized then return self end
    for _,name in ipairs({"logger","db","cache"}) do
        if self.container:has(name) then local s=self.container:get(name); if s.init_worker then s:init_worker() end end
    end
    self.worker_initialized=true
    if type(self.config.init_worker)=="function" then self.config.init_worker(self) end
    return self
end
function Application:new_context(request,response)
    assert(self.booted,"application must be booted before creating context")
    return Context(self,request,response)
end
function Application:make(name,...) return self.container:make(name,...) end
function Application:get(name) return self.container:get(name) end
function Application:handle(ctx)
    assert(ctx,"context is required")
    return Exception.boundary(self,ctx,function()
        if self.middleware and self.middleware.handle then return self.middleware:handle(ctx,function(c) return self:dispatch(c) end)
        elseif self.middleware and self.middleware.run then return self.middleware:run(ctx,function(c) return self:dispatch(c) end) end
        return self:dispatch(ctx)
    end)
end
function Application:dispatch(ctx)
    if not self.router then error("router is not configured") end
    local handler,result=self.router:dispatch(ctx)
    if not handler then
        if (result or "not_found")=="method_not_allowed" then return ctx:text("Method Not Allowed",405) end
        return ctx:text("Not Found",404)
    end
    if type(handler)=="function" then return handler(ctx) end
    if self.invoker then
        local value,err=self.invoker:invoke(handler,ctx,result and result.params)
        if value~=nil then return value end
        if err=="controller_not_found" or err=="action_not_found" then return ctx:text("Not Found",404) end
        if err then error(err) end
    end
    return handler
end
function Application:shutdown()
    for _,name in ipairs({"cache","db","logger"}) do
        if self.container:has(name) then local s=self.container:get(name); if s.shutdown then s:shutdown() elseif s.close then s:close() end end
    end
    self.worker_initialized=false; return self
end
return Application
