--- Tilua.app
--- Slim application core (refactored from the original 600+ line monolith).
--- Public API remains compatible with existing applications.

local class      = require("Tilua.utils.class")
local lw_utils   = require("Tilua.utils.util")
local path       = require("Tilua.utils.path")
local import     = lw_utils.import
local combine    = lw_utils.extend
local bind1      = lw_utils.bind1

local lifecycle  = require("Tilua.core.lifecycle")

---@class app
local App = class.define()

-------------------------------------------------
-- Construction & lazy loaders
-------------------------------------------------

function App:_construct()
    -- Prefer new name; shim keeps Tilua.midware working
    self.midware = require("Tilua.middleware")(self)
    self.on_app_handled_callbacks = {}
end


function App:get_dispatcher()
    local name = self.config.dispatch or "Tilua.http.dispatcher"
    self.logger:debug("init dispatcher:", name)
    local Dispatch = import(name)
    assert(Dispatch and Dispatch.run, "dispatcher must expose a run method")
    self.dispatcher = Dispatch(self)
    return self.dispatcher
end

function App:get_request()
    self.request = import("Tilua.http.request").capture(self)
    return self.request
end

function App:get_response()
    self.response = import("Tilua.http.response")(self)
    return self.response
end


function App:get_cache()
    self.cache = require("Tilua.cache")(self.config, self.logger)
    self:on_app_handled(bind1(self.cache.close, self.cache))
    return self.cache
end

function App:get_db()
    self.db = require("Tilua.db")({
        ctx    = self.config,
        logger = self.logger,
    })
    self:on_app_handled(bind1(self.db.close, self.db))
    return self.db
end

function App:get_model()
    self.model = require("Tilua.model")(self)
    return self.model
end

function App:get_logger()
    local Logger = self._logger_class or require("Tilua.log")
    self.logger = Logger.new(self.config.log)
    return self.logger
end

function App:get_view()
    self.view = import("Tilua.view")(self)
    return self.view
end

function App:get_config(key)
    if key then
        return lw_utils.index_value(self.config, key)
    end
    return self.config
end

function App:unpack()
    return self.request, self.response, self.cache, self.config
end

-------------------------------------------------
-- Config & route loading
-------------------------------------------------

function App:load_config()
    local cfg = {}
    local appname = self.name

    self.path = path.get_module_path(appname, "app")

    -- 1. framework defaults
    combine(cfg, import("Tilua.config.default") or {})
    -- 2. application defaults
    combine(cfg, import(appname, "config", "default") or {})
    -- 3. environment-specific (dev / prod / …)
    if self.status then
        combine(cfg, import(appname, "config", self.status) or {})
    end

    self.config = cfg
    return cfg
end

function App:load_route()
    local appname = self.name
    self.route = import("Tilua.http.router")
    self.route.set_app_name(appname)

    local routes = import(appname .. ".routes")
    if type(routes) == "function" then
        routes(self, self.route)
    end

    self.route.init_rule_caches(self.config.route or {})
end


-------------------------------------------------
-- Lifecycle (delegated)
-------------------------------------------------

App.init_by_lua          = lifecycle.init_by_lua
App.is_inited_by_lua     = lifecycle.is_inited_by_lua
App.init_worker_by_lua   = lifecycle.init_worker_by_lua
App.set_by_lua           = lifecycle.set_by_lua
App.is_setted_by_lua     = lifecycle.is_setted_by_lua
App.rewrite_by_lua       = lifecycle.rewrite_by_lua
App.access_by_lua        = lifecycle.access_by_lua
App.content_by_lua       = lifecycle.content_by_lua
App.log_by_lua           = lifecycle.log_by_lua

-- keep old alias used in some examples
function App:is_app_inited()
    return self:is_inited_by_lua()
end

-------------------------------------------------
-- Runtime helpers
-------------------------------------------------

function App:on_app_handled(cb)
    table.insert(self.on_app_handled_callbacks, cb)
end

--- Built-in health endpoint (Phase 3 production default)
local function try_health(self)
    local path = self.config and self.config.health_path or "/health"
    local uri = (self.request and self.request.path_info) or ngx.var.uri or ""
    if uri ~= path and uri ~= path .. "/" then
        return false
    end
    local body = '{"status":"ok","app":"' .. (self.name or "tilua") .. '","pid":' .. tostring(ngx.worker.pid()) .. "}"
    local resp = self.response
    resp.status = 200
    resp.headers = resp.headers or {}
    resp.headers["Content-Type"] = "application/json; charset=utf-8"
    resp.body = body
    return true
end

--- Main entry used by content_by_lua_block
function App:run()
    if try_health(self) then
        return self.response
    end
    -- route.run returns (matched:boolean, best_rule) after validation
    local matched, router = self.route.run(self)
    return self.dispatcher:run(matched, router)
end


return App

