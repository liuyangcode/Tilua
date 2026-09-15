--- Tilua.core.lifecycle
--- OpenResty phase helpers extracted from the original monolithic app.lua
--- Keeps the same public API so existing applications continue to work.

local path       = require("Tilua.utils.path")
local lw_utils   = require("Tilua.utils.util")
local import     = lw_utils.import
local combine    = lw_utils.extend
local bind1      = lw_utils.bind1
local path_join  = path.join
local path_exists = path.isdir

local M = {}

local function ensure_dir(p)
    if path_exists(p) then
        return true
    end
    -- try Penlight if present, else shell mkdir
    local ok_pl, pl_dir = pcall(require, "pl.dir")
    if ok_pl and pl_dir.makepath then
        local _, err = pl_dir.makepath(p)
        if err then
            error("cannot create directory " .. p .. ": " .. tostring(err))
        end
        return true
    end
    local cmd = "mkdir -p " .. p:gsub("'", "'\\''")
    local ret = os.execute(cmd)
    if ret ~= 0 and ret ~= true then
        error("cannot create directory " .. p)
    end
    return true
end

local function init_view_engine(root)
    local template = require("resty.template")

    local view_path       = path_join(root, "view", "")
    local cache_path      = path_join(root, "cache", "")
    local view_cache_path = path_join(cache_path, "view", "")
    local html_cache_path = path_join(cache_path, "html", "")

    for _, p in ipairs({ cache_path, view_cache_path, html_cache_path }) do
        ensure_dir(p)
    end


    local view_engine = template.new({ root = root })
    return {
        template            = view_engine,
        view                = view_path,
        root                = root,
        cache_key_prefix    = view_path,
        view_cache_path     = path_join("cache", "view", ""),
        view_cache_abs_path = view_cache_path,
        html_cache_path     = html_cache_path,
    }
end

--- init_by_lua (master / config load)
function M.init_by_lua(app)
    if app:is_inited_by_lua() then
        return true
    end

    local cfg = app:load_config()
    app:load_route()

    -- reload middleware manager with current config
    local mw = import("Tilua.middleware")
    if mw and mw.load then
        mw.load(cfg)
    end


    app.view_engine = init_view_engine(app.path)
    if app.view_engine.template and app.view_engine.template.caching then
        app.view_engine.template.caching(not app.debug)
    end

    cfg.log = cfg.log or {}
    cfg.log.path = path_join(app.path, cfg.log.path or "log")

    local log_mod = import("Tilua.log")
    if log_mod and log_mod.init then
        -- store the logger class for later lazy init
        app._logger_class = log_mod.init(cfg.log)
    end

    if type(app.on_init_by_lua) == "function" then
        app:on_init_by_lua()
    end

    app.pid = ngx.worker.pid()
    return true
end

function M.is_inited_by_lua(app)
    return (app.pid or 0) > 0
end

--- init_worker_by_lua
function M.init_worker_by_lua(app)
    ngx.log(ngx.DEBUG, "Tilua.init_worker_by_lua ", app.name or "?")
    if type(app.on_init_worker) == "function" then
        app:on_init_worker()
    end
    if type(app.warming_up) == "function" then
        ngx.timer.at(0, bind1(app.warming_up, app()))
    end
end

--- set_by_lua – create per-request context
function M.set_by_lua(app)
    if not app:is_inited_by_lua() then
        app:init_by_lua()
    end

    ngx.update_time()
    if lw_utils.elapse_time_start then
        lw_utils.elapse_time_start("app_execution_time")
    end

    local ctx = app()   -- instantiate
    if type(ctx.on_app_init) == "function" then
        ctx:on_app_init()
    end

    ngx.ctx.ctx = ctx
    return ctx
end

function M.is_setted_by_lua()
    return ngx.ctx.ctx
end

function M.rewrite_by_lua(app)
    local ctx = ngx.ctx.ctx
    if not ctx then
        ctx = app:set_by_lua()
    end
    if type(ctx.on_rewrite) == "function" then
        ctx:on_rewrite()
    end
end

function M.access_by_lua(app)
    local ctx = ngx.ctx.ctx
    if not ctx then
        ctx = app:set_by_lua()
    end
    if type(ctx.on_access) == "function" then
        ctx:on_access()
    end
end

function M.content_by_lua(app)
    local ctx = ngx.ctx.ctx
    if not ctx then
        ctx = app:set_by_lua()
    end
    return ctx:run()
end

function M.log_by_lua(app)
    local ctx = ngx.ctx.ctx
    if ctx and type(ctx.on_log) == "function" then
        ctx:on_log()
    end
    -- run registered on_app_handled callbacks (close db, cache …)
    if ctx and ctx.on_app_handled_callbacks then
        for _, cb in ipairs(ctx.on_app_handled_callbacks) do
            pcall(cb)
        end
    end
end

return M
